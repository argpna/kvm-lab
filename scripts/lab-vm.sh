#!/usr/bin/env bash
# Create or destroy the libvirt VM of one inventory host with OpenTofu (one state file per host).
# Usage: scripts/lab-vm.sh up|destroy <host>
set -euo pipefail

action=${1:?usage: lab-vm.sh up|destroy <host>}
host=${2:?usage: lab-vm.sh up|destroy <host>}
root=$(cd "$(dirname "$0")/.." && pwd)
base_pool=${LAB_BASE_POOL:-lab-base}
vm_pool=${LAB_VM_POOL:-lab-vms}

mkdir -p "$root/.lab/hosts" "$root/.lab/state"
host_file=$root/.lab/hosts/$host.json
"$root/inventory/inventory.py" --host "$host" >"$host_file"

image=$(jq -r .image "$host_file")
base=$(virsh -c qemu:///system vol-list --pool "$base_pool" |
  awk -v p="$image-" 'index($1, p) == 1 && $1 ~ /-[0-9]+\.qcow2$/ {print $1}' | sort | tail -n 1)
if [ -z "$base" ]; then
  echo "$host: no base image '$image-<date>.qcow2' in pool $base_pool (build the image first)" >&2
  exit 1
fi

args=(-no-color -input=false -state="$root/.lab/state/$host.tfstate"
  -var "host_file=$host_file" -var "base_volume=$base" -var "repo_root=$root"
  -var "ssh_pubkey_file=$root/.lab/ssh/id_ed25519.pub" -var "base_pool=$base_pool" -var "vm_pool=$vm_pool")

case $action in
  up) tofu -chdir="$root/tofu" apply -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  destroy) tofu -chdir="$root/tofu" destroy -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac
