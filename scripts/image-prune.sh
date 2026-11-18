#!/usr/bin/env bash
# List old base images in lab-base, or delete them with --delete.
# An image is old when a newer file with the same name prefix exists and no disk in lab-vms uses it.
# Usage: scripts/image-prune.sh [--delete]
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
delete=0
case ${1:-} in
  "") ;;
  --delete) delete=1 ;;
  *) echo "Usage: image-prune.sh [--delete]" >&2; exit 2 ;;
esac

virsh_cmd=(virsh -c qemu:///system)
base_pool=${LAB_BASE_POOL:-lab-base}
vm_pool=${LAB_VM_POOL:-lab-vms}

images=$("${virsh_cmd[@]}" vol-list --pool "$base_pool" | awk '$1 ~ /-[0-9]+\.qcow2$/ {print $1}' | sort)

backing=$(
  for vol in $("${virsh_cmd[@]}" vol-list --pool "$vm_pool" | awk 'NR > 2 && NF {print $1}'); do
    "${virsh_cmd[@]}" vol-dumpxml --pool "$vm_pool" "$vol" | sed -n '/<backingStore>/,/<\/backingStore>/ s|.*<path>\(.*\)</path>.*|\1|p'
  done | xargs -r -n1 basename | sort -u
)

found=0
while read -r name; do
  [ -n "$name" ] || continue
  prefix=${name%-*}
  newest=$(grep -E "^${prefix//./\\.}-[0-9]+\.qcow2$" <<<"$images" | tail -n 1)
  [ "$name" != "$newest" ] || continue
  if grep -qxF "$name" <<<"$backing"; then
    echo "Keeping $name because a disk in $vm_pool uses it."
    continue
  fi
  found=1
  if [ "$delete" = 1 ]; then
    "${virsh_cmd[@]}" vol-delete --pool "$base_pool" "$name"
    rm -f "$root/.lab/images/$name.fingerprint"
  else
    echo "Would delete $name because the newest volume is $newest."
  fi
done <<<"$images"

[ "$found" = 1 ] || echo "Nothing to prune."
[ "$delete" = 1 ] || [ "$found" = 0 ] || echo "Run 'scripts/lab image prune --delete' to delete these volumes."
