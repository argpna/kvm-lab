#!/usr/bin/env bash
# Create, stop or destroy libvirt VMs defined in the inventory.
# Usage: scripts/lab-vm.sh up|stop|destroy <host>
# stop shuts the VM down and keeps its disk; STOP_TIMEOUT (seconds, default 120) and FORCE=1 apply.
set -euo pipefail

action=${1:?usage: lab-vm.sh up|stop|destroy <host>}
host=${2:?usage: lab-vm.sh up|stop|destroy <host>}
root=$(cd "$(dirname "$0")/.." && pwd)
base_pool=${LAB_BASE_POOL:-lab-base}
vm_pool=${LAB_VM_POOL:-lab-vms}

if [ "$action" = stop ]; then
  domain=lab-$host
  state=$(virsh -c qemu:///system domstate "$domain") || { echo "The host $host has no domain named $domain." >&2; exit 1; }
  if [ "$state" = "shut off" ]; then
    echo "$host is already stopped."
    exit 0
  fi
  virsh -c qemu:///system shutdown "$domain" >/dev/null
  for ((i = 0; i < ${STOP_TIMEOUT:-120}; i++)); do
    [ "$(virsh -c qemu:///system domstate "$domain")" = "shut off" ] && { echo "$host has stopped."; exit 0; }
    sleep 1
  done
  if [ "${FORCE:-}" = 1 ]; then
    virsh -c qemu:///system destroy "$domain" >/dev/null
    echo "$host was forced off after ${STOP_TIMEOUT:-120} seconds."
    exit 0
  fi
  echo "$host is still running after ${STOP_TIMEOUT:-120} seconds. Set FORCE=1 to power it off." >&2
  exit 1
fi

mkdir -p "$root/.lab/hosts" "$root/.lab/state"
host_file=$root/.lab/hosts/$host.json
"$root/inventory/inventory.py" --host "$host" >"$host_file"

image=$(jq -r .image "$host_file")
lab_user=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["lab_user"])' "$root/inventory/group_vars/all/credentials.yml")
base=${LAB_BASE_VOLUME:-$(virsh -c qemu:///system vol-list --pool "$base_pool" |
  awk -v p="$image-" 'index($1, p) == 1 && $1 ~ /-[0-9]+\.qcow2$/ {print $1}' | sort | tail -n 1)}
if [ -z "$base" ]; then
  echo "The host $host has no base image named '$image-<date>.qcow2' in pool $base_pool. Build the image first." >&2
  exit 1
fi

# Firmware comes from the image entry in images/windows.yml (bios when the image is not listed).
firmware=$(python3 -I -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["images"].get(sys.argv[2], {}).get("firmware", "bios"))' "$root/images/windows.yml" "$image")

# The overlay disk must not be smaller than the base image (GiB, rounded up).
base_bytes=$(virsh -c qemu:///system vol-info --bytes --pool "$base_pool" "$base" | awk '/^Capacity:/ {print $2}')
base_gib=$(((base_bytes + 1073741823) / 1073741824))

args=(-no-color -input=false -state="$root/.lab/state/$host.tfstate"
  -var "host_file=$host_file" -var "base_volume=$base" -var "firmware=$firmware" -var "base_gib=$base_gib" -var "repo_root=$root"
  -var "ssh_pubkey_file=$root/.lab/ssh/id_ed25519.pub" -var "lab_user=$lab_user" -var "base_pool=$base_pool" -var "vm_pool=$vm_pool")

case $action in
  up) tofu -chdir="$root/tofu" apply -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  destroy) tofu -chdir="$root/tofu" destroy -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  *) echo "Unknown action: $action" >&2; exit 2 ;;
esac
