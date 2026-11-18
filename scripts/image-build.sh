#!/usr/bin/env bash
# Build a Windows base image from the Microsoft evaluation VHD and upload it to lab-base.
# Usage: scripts/image-build.sh <image> (an entry of images/windows.yml, for example windows-2022)
# The VM account is lab_user with lab_password from inventory/group_vars/all/credentials.yml.
# Downloads are cached in CACHE_DIR (default ~/vm-builds/common), work files go to BUILD_DIR
# (default ~/vm-builds/<image>). Needs qemu-img, libguestfs-tools (virt-customize, virt-win-reg) and virsh.
set -euo pipefail

image=${1:?usage: image-build.sh <image> (see images/windows.yml)}
root=$(cd "$(dirname "$0")/.." && pwd)
manifest=$root/images/windows.yml
creds=$root/inventory/group_vars/all/credentials.yml
cache=${CACHE_DIR:-$HOME/vm-builds/common}
build=${BUILD_DIR:-$HOME/vm-builds/$image}
virsh_cmd=(virsh -c qemu:///system)
export LIBGUESTFS_BACKEND=direct

# Print the value at a dotted path of a yaml file.
yget() {
    python3 -I -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[k]
print(d)' "$1" "$2"
}

# Download url to dest unless dest already matches sha256, then verify it.
fetch() {
    local url=$1 sha=$2 dest=$3
    if [ -f "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$sha" ]; then
        return
    fi
    curl -fL -C - -o "$dest.part" "$url"
    if [ "$(sha256sum "$dest.part" | cut -d' ' -f1)" != "$sha" ]; then
        echo "sha256 of $url differs from the pin in images/windows.yml; the file is kept as $dest.part" >&2
        exit 1
    fi
    mv "$dest.part" "$dest"
}

yget "$manifest" "images.$image.url" >/dev/null || { echo "unknown image $image (see images/windows.yml)" >&2; exit 2; }
for tool in qemu-img virt-customize virt-win-reg virsh; do
    command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done

name=$image-$(date +%Y%m%d%H%M)
if "${virsh_cmd[@]}" vol-info --pool lab-base "$name.qcow2" >/dev/null 2>&1; then
    echo "$name.qcow2 already exists in lab-base" >&2
    exit 1
fi

mkdir -p "$cache" "$build"
format=$(yget "$manifest" "images.$image.format")
disk_src=$cache/$image-eval.$([ "$format" = vpc ] && echo vhd || echo "$format")
virtio=$cache/virtio-win-$(yget "$manifest" virtio_win.sha256 | cut -c1-12).iso
pwsh_msi=$cache/$(basename "$(yget "$manifest" extras.powershell.url)")
pester_ver=$(yget "$manifest" extras.pester.version)
pester_pkg=$cache/Pester.$pester_ver.nupkg
sysint_zip=$cache/SysinternalsSuite-$(yget "$manifest" extras.sysinternals.sha256 | cut -c1-12).zip

fetch "$(yget "$manifest" "images.$image.url")" "$(yget "$manifest" "images.$image.sha256")" "$disk_src"
fetch "$(yget "$manifest" virtio_win.url)" "$(yget "$manifest" virtio_win.sha256)" "$virtio"
fetch "$(yget "$manifest" extras.powershell.url)" "$(yget "$manifest" extras.powershell.sha256)" "$pwsh_msi"
fetch "$(yget "$manifest" extras.pester.url)" "$(yget "$manifest" extras.pester.sha256)" "$pester_pkg"
fetch "$(yget "$manifest" extras.sysinternals.url)" "$(yget "$manifest" extras.sysinternals.sha256)" "$sysint_zip"

stage=$build/stage
disk=$build/$name.qcow2
out=$build/$name.final.qcow2
# The stage directory holds the lab password; always remove it with the temporary disks.
trap 'command rm -rf -- "$stage" "$disk" "$out"' EXIT
rm -rf "$stage"
mkdir -p "$stage"
python3 -I - "$root/images/windows/unattend.xml" "$creds" "$stage/unattend.xml" "$pester_pkg" "$pester_ver" "$sysint_zip" "$stage" <<'PY'
import sys, zipfile
from xml.sax.saxutils import escape
import yaml
unattend, creds, out, pester_pkg, pester_ver, sysint_zip, stage = sys.argv[1:]
c = yaml.safe_load(open(creds))
text = open(unattend).read()
text = text.replace("@LAB_USER@", escape(c["lab_user"])).replace("@LAB_PASSWORD@", escape(c["lab_password"]))
open(out, "w").write(text)
# A nupkg is a zip; the module is the folder content without the packaging files.
skip = ("[Content_Types].xml", "_rels/", "package/")
with zipfile.ZipFile(pester_pkg) as z:
    for m in z.infolist():
        if m.filename.startswith(skip) or m.filename.endswith(".nuspec"):
            continue
        z.extract(m, f"{stage}/pester/{pester_ver}")
with zipfile.ZipFile(sysint_zip) as z:
    z.extractall(f"{stage}/Sysinternals")
PY
cp "$root/images/windows/first-logon.ps1" "$stage/first-logon.ps1"
cp "$pwsh_msi" "$stage/pwsh.msi"

echo "converting $disk_src"
qemu-img convert -f "$format" -O qcow2 "$disk_src" "$disk"

modules="/Program Files/WindowsPowerShell/Modules/Pester"
virt-customize -a "$disk" \
    --inject-virtio-win "$virtio" \
    --mkdir /Windows/Setup/Scripts \
    --copy-in "$stage/first-logon.ps1:/Windows/Setup/Scripts" \
    --copy-in "$stage/pwsh.msi:/Windows/Setup/Scripts" \
    --mkdir /Windows/Panther/Unattend \
    --copy-in "$stage/unattend.xml:/Windows/Panther/Unattend" \
    --mkdir /Tools \
    --copy-in "$stage/Sysinternals:/Tools" \
    --mkdir "$modules" \
    --copy-in "$stage/pester/$pester_ver:$modules" \
    --delete "$modules/3.4.0"
virt-win-reg --merge "$disk" "$root/images/windows/baseline.reg"
if [ "$(yget "$manifest" "images.$image.tls13")" = True ]; then
    virt-win-reg --merge "$disk" "$root/images/windows/tls13.reg"
fi

qemu-img convert -c -O qcow2 "$disk" "$out"
size=$(qemu-img info --output=json "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
"${virsh_cmd[@]}" vol-create-as lab-base "$name.qcow2" "$size" --format qcow2
"${virsh_cmd[@]}" vol-upload --pool lab-base "$name.qcow2" "$out"
echo "uploaded $name.qcow2 to lab-base"
echo "make the qcow2 read-only: sudo chmod 0444 /var/lib/libvirt/images/lab-base/$name.qcow2"
