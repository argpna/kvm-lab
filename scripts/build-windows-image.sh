#!/usr/bin/env bash
# Build a Windows base image with an external packer-windoze checkout and upload it to lab-base.
# Usage: scripts/build-windows-image.sh <version> [extra ansible-playbook args]   (example: 2022)
# The image account is lab_user with lab_password from inventory/group_vars/all/credentials.yml.
# Set SKIP_UPDATES=true to skip Windows Update. The build takes 1 to 3 hours.
# Environment: PACKER_WINDOZE_DIR, PACKER_WINDOZE_VENV, BUILD_DIR (defaults below).
set -euo pipefail

version=${1:?usage: build-windows-image.sh <version> [ansible-playbook args]}
shift
checkout=${PACKER_WINDOZE_DIR:-$HOME/projects/packer-windoze}
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
echo "packer-windoze commit: $(git -C "$checkout" rev-parse --short HEAD)"
cd "$checkout"
PATH="$venv/bin:$PATH" ansible-playbook main.yml --limit "*$version" --skip-tags box \
    -e headless=true -e "output_dir=$build" -e "skip_updates=${SKIP_UPDATES:-false}" \
    -e "setup_username=$lab_user" -e "setup_password=$lab_password" "$@"

disk="$build/$version/qemu/$version-vm.qcow2"
out="$build/$version/$name.qcow2"
qemu-img convert -p -O qcow2 "$disk" "$out"
size=$(qemu-img info --output=json "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
"${virsh_cmd[@]}" vol-create-as lab-base "$name.qcow2" "$size" --format qcow2
"${virsh_cmd[@]}" vol-upload --pool lab-base "$name.qcow2" "$out"
echo "uploaded $name.qcow2 to lab-base"
echo "make it read-only: sudo chmod 0444 /var/lib/libvirt/images/lab-base/$name.qcow2"
