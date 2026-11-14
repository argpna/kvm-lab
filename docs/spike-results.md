# Phase 1 spike results

Provider: dmacvicar/libvirt 0.9.9 (0.9.0 lacks Hyper-V, memory backing and SMBIOS; do not use).

## Schema check (tofu providers schema, no VM booted)

| Item | Result | Attribute |
|---|---|---|
| Overlay volume with backing image | pass | libvirt_volume.backing_store |
| NIC with fixed MAC on a network | pass | devices.interfaces.mac.address, source, model.type |
| BIOS firmware, machine type pc | pass | os.type_machine, os.firmware |
| virtio disk, QXL video, SPICE | pass | devices.disks, devices.videos.model.type, devices.graphics.spice |
| clock localtime, hypervclock timer | pass | clock.offset, clock.timer.name |
| Hyper-V relaxed, vapic, spinlocks | pass | features.hyper_v.* |
| SMBIOS OEM string | pass | sys_info.smbios.oem_strings.entry |
| memfd memory backing | pass | memory_backing.memory_source.type, memory_access.mode |
| virtiofs filesystem device | pass | devices.filesystems.driver.type, source.mount.dir |
| cloud-init seed ISO | pass | resource libvirt_cloudinit_disk (user_data, meta_data, network_config) |

## Needs a running VM (not yet tested)

- apply with -target / -replace for one host and its overhead
- two applies at the same time (state lock)
- guest behaviour: cloud-init multi NIC, Windows first boot

## Live test (provider 0.9.9, OpenTofu 1.13.9, Ubuntu 22.04 image)

| Item | Result | Notes |
|---|---|---|
| Overlay volume with backing image | pass | root filesystem grows to the overlay size on first boot |
| Boot from backing image, cloud-init seed | pass | user, key, passwordless sudo, hostname, DHCP on a fixed MAC |
| Create one host | pass | about 3 s for apply; address leased about 8 s after start |
| Replace one domain (-replace) | pass | about 5 s |
| Two applies on one state at the same time | fail | second apply fails with "Error acquiring the state lock" |
| One workspace per host, two applies at once | pass | both finished in about 3.4 s |
| Destroy one host without touching another | pass | about 2.7 s |

Findings:
- Linux guests must use machine type pc (i440fx). With q35 the Ubuntu 22.04 kernel (5.15) cannot
  use the virtio devices behind PCIe root ports, and boot stops at the initramfs shell.
- The cloud image file name inside the vendor release directory is
  ubuntu-22.04-server-cloudimg-amd64.img, not jammy-server-cloudimg-amd64.img. Use the dated
  release directory (release-20261106) for a stable URL and checksum.
- Decision: one workspace per host (separate state and lock), one config for a single host.
  The pools (lab-base, lab-vms) are created outside OpenTofu so no host owns them.

Not yet tested: multi-NIC network-config, Windows boot, virtiofs, other distros.

## Inventory and Windows image findings

- All 19 inventory hosts have exactly one NIC, so no host is multi-NIC today. The multi-NIC
  default-route risk is latent: the inventory model allows several NICs per host.
- packer-windoze has no licence upstream (jborean93) and none in the argpna fork. Do not copy its
  files into this repo; use a pinned external checkout.
- --skip-tags box stops the build after sysprep and shutdown (the box play is tagged box).
- The Windows Updates step (roles/update) always installs everything. Skipping it needs a patch.
- inventory.yml in packer-windoze has 2012, 2012r2, 2016, 2019 and 2022, but no 2025 entry.
- The SMBIOS hostname logic (set-hostname.ps1 and the sysprep template edits) exists only as
  uncommitted changes in the local packer-windoze clone. The box the lab ran on does not have it.
- Build host: mkisofs, qemu-system-x86_64 present; pigz missing (only needed for the box step).

## Windows Server 2022 image and first boot (build with skip_updates=true)

- First build run: install and provisioning passed; sysprep failed in about 1 s with 0x3cf2
  (AppxSysprep: Microsoft.MicrosoftEdge.Stable installed for one user, not provisioned for all).
  The shutdown task reports result 0 because it only launches sysprep (/quiet hides the error),
  so Ansible waited 300 s for a shutdown that never began.
- Fix tested by hand in the VM: Get-AppxPackage -AllUsers -Name Microsoft.MicrosoftEdge.Stable |
  Remove-AppxPackage -AllUsers, then rerun the packer-shutdown task. Sysprep finished and the VM
  powered off. The recipe still needs this step added.
- Image: 40 GiB virtual, 40 GB on disk after the build, 11 GB after qemu-img convert.
- Overlay boot (tofu/spike-win): domain XML matches the Vagrant reference (pc-i440fx, memfd shared,
  hyper_v relaxed/vapic/spinlocks, localtime clock with hypervclock, virtio disk and NIC, QXL,
  SPICE, USB tablet). Create takes about 3 s.
- First boot: PSRP login over HTTPS 5986 worked 169 s after start (limit was 900 s).
  Hostname is random (WIN-xxxx) because the SMBIOS hostname change was dropped.
  Time zone is UTC (host is UTC). slmgr reports Licensed.
