#!/usr/bin/env bash
# Build a Windows base image with packer-windoze and upload it to lab-base directory.
# Usage: scripts/build-windows-image.sh <version> [extra ansible-playbook args] (example: 2022)
# The image account is lab_user with lab_password from inventory/group_vars/all/credentials.yml.
# Set SKIP_UPDATES=true to skip Windows Update. The build takes 1 to 3 hours.
# The packer-windoze checkout is pinned in images/packer-windoze.yml (default .lab/packer-windoze).
# Environment: PACKER_WINDOZE_DIR, PACKER_WINDOZE_VENV, BUILD_DIR (defaults below).
set -euo pipefail

version=${1:?usage: build-windows-image.sh <version> [ansible-playbook args]}
shift
root=$(cd "$(dirname "$0")/.." && pwd)
pin=$root/images/packer-windoze.yml
pin_repo=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["repo"])' "$pin")
pin_commit=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["commit"])' "$pin")
checkout=${PACKER_WINDOZE_DIR:-$root/.lab/packer-windoze}
venv=${PACKER_WINDOZE_VENV:-$HOME/projects/packer-windoze-venv}
build=${BUILD_DIR:-$HOME/vm-builds}
date=$(date +%Y%m%d%H%M)
name=windows-$version-$date
virsh_cmd=(virsh -c qemu:///system)
creds="$(dirname "$0")/../inventory/group_vars/all/credentials.yml"
lab_user=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["lab_user"])' "$creds")
lab_password=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["lab_password"])' "$creds")

if "${virsh_cmd[@]}" vol-info --pool lab-base "$name.qcow2" >/dev/null 2>&1; then
    echo "$name.qcow2 already exists in lab-base" >&2
    exit 1
fi

mkdir -p "$build"
if [ -z "${PACKER_WINDOZE_DIR:-}" ]; then
    [ -d "$checkout/.git" ] || git clone -q "$pin_repo" "$checkout"
    if [ "$(git -C "$checkout" rev-parse HEAD)" != "$pin_commit" ]; then
        git -C "$checkout" fetch -q origin
        git -C "$checkout" checkout -q --detach "$pin_commit"
    fi
fi
if [ "$(git -C "$checkout" rev-parse HEAD)" != "$pin_commit" ] || [ -n "$(git -C "$checkout" status --porcelain)" ]; then
    echo "$checkout is not clean at pinned commit $pin_commit (see images/packer-windoze.yml)" >&2
    exit 1
fi
echo "packer-windoze commit: $(git -C "$checkout" rev-parse --short HEAD)"
cd "$checkout"
PATH="$venv/bin:$PATH" ansible-playbook main.yml --limit "*$version" --skip-tags box \
    -e headless=true -e "output_dir=$build" -e "skip_updates=${SKIP_UPDATES:-false}" \
    -e "setup_username=$lab_user" -e "setup_password=$lab_password" "$@"

disk="$build/$version/qemu/$version-vm.qcow2"
out="$build/$version/$name.qcow2"
qemu-img convert -c -p -O qcow2 "$disk" "$out"
size=$(qemu-img info --output=json "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
"${virsh_cmd[@]}" vol-create-as lab-base "$name.qcow2" "$size" --format qcow2
"${virsh_cmd[@]}" vol-upload --pool lab-base "$name.qcow2" "$out"
echo "uploaded $name.qcow2 to lab-base"
command rm -f -- "$out" "$disk"
echo "make the qcow2 read-only: sudo chmod 0444 /var/lib/libvirt/images/lab-base/$name.qcow2"
