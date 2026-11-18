# shellcheck shell=bash
# Helpers shared by image-build-linux.sh and image-build-windows.sh (sourced, not run).
# Every build creates a new volume <image>-<YYYYMMDDHHMM>.qcow2 in lab-base and never replaces one.
# The build records a fingerprint of its inputs in .lab/images/<volume>.fingerprint; a build is
# skipped while the newest volume of the image has the same fingerprint as the current inputs.

image_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image_records=$image_root/.lab/images
image_pool=${LAB_BASE_POOL:-lab-base}
image_virsh=(virsh -c qemu:///system)

# Print the newest volume of image $1 in lab-base, or nothing when there is none.
image_newest() {
    "${image_virsh[@]}" vol-list --pool "$image_pool" | awk '{print $1}' |
        grep -E "^${1//./\\.}-[0-9]{12}\.qcow2$" | sort | tail -n 1 || true
}

# Succeed when the newest volume of image $1 was built from inputs with fingerprint $2.
image_is_current() {
    local vol
    vol=$(image_newest "$1")
    [ -n "$vol" ] && [ "$(cat "$image_records/$vol.fingerprint" 2>/dev/null)" = "$2" ]
}

# Print a new volume name (without .qcow2) for image $1; fail when the name is taken.
image_new_name() {
    local name
    name=$1-$(date +%Y%m%d%H%M)
    if "${image_virsh[@]}" vol-info --pool "$image_pool" "$name.qcow2" >/dev/null 2>&1; then
        echo "$name.qcow2 already exists in $image_pool. Volume names are timestamped to the minute, so wait a minute and try again." >&2
        return 1
    fi
    echo "$name"
}

# Upload qcow2 file $2 as volume $1.qcow2 and record fingerprint $3; remove the volume if the upload fails.
image_upload() {
    local name=$1 file=$2 fingerprint=$3 size
    size=$(qemu-img info --output=json "$file" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
    "${image_virsh[@]}" vol-create-as "$image_pool" "$name.qcow2" "$size" --format qcow2
    "${image_virsh[@]}" vol-upload --pool "$image_pool" "$name.qcow2" "$file" || {
        "${image_virsh[@]}" vol-delete --pool "$image_pool" "$name.qcow2"
        echo "The upload of $name.qcow2 failed, so the partial volume was removed." >&2
        return 1
    }
    mkdir -p "$image_records"
    echo "$fingerprint" >"$image_records/$name.qcow2.fingerprint"
}
