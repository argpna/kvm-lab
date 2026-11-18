#!/usr/bin/env bash
# Build the Linux base images listed in images/linux.yml. For each image, the script downloads the
# cloud image, verifies its hash, and uploads it to the libvirt pool lab-base as
# <image>-<YYYYMMDDHHMM>.qcow2.
# Usage: scripts/image-build-linux.sh [--force] [image ...] (default: all).
set -euo pipefail

force=0
if [ "${1:-}" = --force ]; then
    force=1
    shift
fi
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/image-lib.sh
. "$root/scripts/image-lib.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

list=$(python3 -I - "$root/images/linux.yml" "$@" <<'PY'
import sys, yaml
images = yaml.safe_load(open(sys.argv[1]))["images"]
want = sys.argv[2:] or list(images)
for key in want:
    if key not in images:
        sys.exit(f"unknown image: {key}")
    i = images[key]
    print(key, i["url"], i["hash"])
PY
)

while read -r key url hash; do
    fingerprint=$(printf '%s\n%s\n' "$url" "$hash" | sha256sum | cut -d' ' -f1)
    if [ "$force" = 0 ] && image_is_current "$key" "$fingerprint"; then
        echo "$key: already up to date; the newest build is $(image_newest "$key"). Use --force to build a new image."
        continue
    fi
    name=$(image_new_name "$key")
    algo=${hash%%:*}
    want=${hash#*:}
    file="$work/$name.qcow2"
    echo "$key: downloading the image from $url"
    curl -fL --http1.1 --retry 3 --retry-all-errors -sS -o "$file" "$url"
    got=$("${algo}sum" "$file" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "$key: $algo checksum mismatch; expected $want but got $got" >&2; exit 1; }
    image_upload "$name" "$file" "$fingerprint"
    rm -f "$file"
    echo "$key: uploaded $name.qcow2 to the libvirt pool."
done <<<"$list"
