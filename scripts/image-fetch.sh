#!/usr/bin/env bash
# Download Linux base images listed in images/manifest.yml into the libvirt pool lab-base.
# Usage: scripts/image-fetch.sh [image ...] (default: all).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
virsh_cmd=(virsh -c qemu:///system)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

list=$(python3 -I - "$root/images/manifest.yml" "$@" <<'PY'
import sys, yaml
images = yaml.safe_load(open(sys.argv[1]))["images"]
want = sys.argv[2:] or list(images)
for key in want:
    if key not in images:
        sys.exit(f"unknown image: {key}")
    i = images[key]
    print(key, i["name"], i["url"], i["hash"])
PY
)

while read -r key name url hash; do
    if "${virsh_cmd[@]}" vol-info --pool lab-base "$name.qcow2" >/dev/null 2>&1; then
        echo "$key: $name.qcow2 already in lab-base"
        continue
    fi
    algo=${hash%%:*}
    want=${hash#*:}
    file="$work/$name.qcow2"
    echo "$key: downloading $url"
    curl -fL --retry 3 -o "$file" "$url"
    got=$("${algo}sum" "$file" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "$key: $algo mismatch (got $got)" >&2; exit 1; }
    size=$(qemu-img info --output=json "$file" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
    "${virsh_cmd[@]}" vol-create-as lab-base "$name.qcow2" "$size" --format qcow2
    "${virsh_cmd[@]}" vol-upload --pool lab-base "$name.qcow2" "$file"
    rm -f "$file"
    echo "$key: uploaded $name.qcow2"
done <<<"$list"
