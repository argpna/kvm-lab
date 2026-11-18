# kvm-lab

Linux and Windows lab VMs on KVM/libvirt, configured by Ansible. VMs are created with OpenTofu
(`dmacvicar/libvirt` provider), one state file per host, from base images stored in a libvirt pool.

## Requirements

- A Linux host with libvirt, QEMU/KVM, `jq` and passwordless `sudo`
- Python 3 (for the venv created by `bootstrap/setup-host-venv.sh`)
- OpenTofu in `.venv/bin/tofu`

## Usage

Commands run through `lab` (`scripts/lab`; `lab` is on the PATH once the venv is activated). A limit is any Ansible limit pattern: a group, `host1,host2` or a
pattern. The default is all hosts, except `destroy`, which requires a host.

    lab up ubuntu2204-sql2022          create the VM
    lab provision ubuntu2204-sql2022   run playbooks/main.yml on the host
    lab stop ubuntu2204-sql2022        shut the VM down (--force powers it off)
    lab destroy ubuntu2204-sql2022     delete the VM
    lab status                         list lab VMs
    lab image list                     list base images
    lab image fetch [name ...]         download Linux images from images/manifest.yml
    lab image build windows-2022       build a Windows image (windows-2022, windows-2025)
    lab image prune [--delete]         list (or delete) old base images no disk uses
    make lint                          ansible-lint, shellcheck, tofu fmt and validate

The VM commands call `make up|provision|stop|destroy|status LIMIT=<limit>`. `lab up` starts a stopped VM again.



## Base images

Base images are read-only qcow2 files named `<image>-<date>.qcow2` in the `lab-base` libvirt pool
(`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest matching file.
Per-VM disks and cloud-init seed ISOs live in the `lab-vms` pool.

Build the images with `lab image fetch` (downloads the cloud images in `images/manifest.yml`) and
`lab image build windows-2019`, `windows-2022` or `windows-2025`. The Windows build downloads the Microsoft evaluation
VHD listed in `images/windows.yml` (the sha256 of every download is pinned), converts it to qcow2 and
copies in the virtio drivers, an unattend.xml, a first-logon script, PowerShell 7, Pester, the
Sysinternals suite and a few registry settings (no automatic updates, and TLS 1.3 on 2022 and 2025; Windows Server 2019 does not support it). It takes a few minutes
once the downloads are cached in `~/vm-builds/common`. The VHD is already generalized, so Windows
specializes on the first boot of each VM. Windows Server 2025 images need UEFI; `images/windows.yml`
records the firmware per image and `scripts/lab-vm.sh` passes it to OpenTofu.

`scripts/image-build-packer.sh` and `images/packer-windoze.yml` (the older packer-windoze build) are no longer used by `lab`.

## License

Base windows roles are forked from jobrean93/ansible-windows. Keeping the original license as is.
