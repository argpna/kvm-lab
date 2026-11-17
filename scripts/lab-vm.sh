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
  state=$(virsh -c qemu:///system domstate "$domain") || { echo "$host: no domain $domain" >&2; exit 1; }
  if [ "$state" = "shut off" ]; then
    echo "$host: already stopped"
    exit 0
  fi
  virsh -c qemu:///system shutdown "$domain" >/dev/null
  for ((i = 0; i < ${STOP_TIMEOUT:-120}; i++)); do
    [ "$(virsh -c qemu:///system domstate "$domain")" = "shut off" ] && { echo "$host: stopped"; exit 0; }
    sleep 1
  done
  if [ "${FORCE:-}" = 1 ]; then
    virsh -c qemu:///system destroy "$domain" >/dev/null
    echo "$host: forced off after ${STOP_TIMEOUT:-120} s"
    exit 0
  fi
  echo "$host: still running after ${STOP_TIMEOUT:-120} s (use FORCE=1 to power it off)" >&2
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
  echo "$host: no base image '$image-<date>.qcow2' in pool $base_pool (build the image first)" >&2
  exit 1
fi

args=(-no-color -input=false -state="$root/.lab/state/$host.tfstate"
  -var "host_file=$host_file" -var "base_volume=$base" -var "repo_root=$root"
  -var "ssh_pubkey_file=$root/.lab/ssh/id_ed25519.pub" -var "lab_user=$lab_user" -var "base_pool=$base_pool" -var "vm_pool=$vm_pool")

case $action in
  up) tofu -chdir="$root/tofu" apply -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  destroy) tofu -chdir="$root/tofu" destroy -auto-approve "${args[@]}" | sed "s/^/$host: /" ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac
