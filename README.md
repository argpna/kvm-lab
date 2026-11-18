# kvm-lab

Linux and Windows lab VMs on KVM/libvirt, configured by Ansible. OpenTofu creates the VMs with the
`dmacvicar/libvirt` provider, one state file per host, from base images stored in a libvirt pool.

## Requirements

- A Linux host with libvirt, QEMU/KVM, `jq`, and passwordless `sudo`
- Python 3, for the virtual environment that `bootstrap/setup-host-venv.sh` creates
- OpenTofu in `.venv/bin/tofu`

## Usage

Run the commands through `lab` (`scripts/lab`), which is on the `PATH` once the virtual environment
is activated. A limit is any Ansible limit pattern: a group, `host1,host2`, or a pattern. The default
is all hosts, except for `destroy`, which requires a host.

    lab up ubuntu2204-sql2022          create the VM
    lab provision ubuntu2204-sql2022   run playbooks/main.yml on the host
    lab stop ubuntu2204-sql2022        shut the VM down (--force powers the VM off)
    lab destroy ubuntu2204-sql2022     delete the VM
    lab status                         list lab VMs
    lab image list                     list base images
    lab image fetch [name ...]         download Linux images from images/manifest.yml
    lab image build windows-2022       build a Windows image (windows-2022, windows-2025)
    lab image prune [--delete]         list (or delete) old base images that no disk uses
    make lint                          ansible-lint, shellcheck, tofu fmt, and tofu validate

## Base images

Base images are read-only qcow2 files named `<image>-<date>.qcow2` in the `lab-base` libvirt pool
(`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest matching file.
Per-VM disks and cloud-init seed ISOs live in the `lab-vms` pool.

Build the images with `lab image fetch`, which downloads the cloud images in `images/manifest.yml`,
and with `lab image build windows-2019`, `lab image build windows-2022`, or
`lab image build windows-2025`. The Windows build downloads the Microsoft evaluation VHD listed in
`images/windows.yml`, converts the VHD to qcow2, and copies in the virtio drivers, an
`unattend.xml` file, a first-logon script, PowerShell 7, Pester, and a few
registry settings. The registry settings disable automatic updates, and the registry settings
enable TLS 1.3 on Windows Server 2022 and Windows Server 2025. Windows Server 2019 does not support
TLS 1.3. The build takes a few minutes once the downloads are cached in `~/vm-builds/common`. The
VHD is already generalized, so Windows specializes on the first boot of each VM. Windows Server
2025 images need UEFI. `images/windows.yml` records the firmware for each image, and
`scripts/lab-vm.sh` passes the firmware to OpenTofu.

## License

The base Windows roles are forked from jobrean93/ansible-windows. The project keeps the original
license as is.
