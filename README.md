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
    lab image build windows-2022       download and build Windows images
    lab image prune [--delete]         list (or delete) old base images no disk uses
    make lint                          ansible-lint, shellcheck, tofu fmt and validate

The VM commands call `make up|provision|stop|destroy|status LIMIT=<limit>`. `lab up` starts a stopped VM again.



## Base images

Base images are read-only qcow2 files named `<image>-<date>.qcow2` in the `lab-base` libvirt pool
(`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest matching file.
Per-VM disks and cloud-init seed ISOs live in the `lab-vms` pool.

Build the images with `lab image fetch` (downloads the cloud images in `images/manifest.yml`) and
`lab image build windows-2022` (builds a Windows image, 1 to 3 hours). The Windows build uses a fork of
packer-windoze. `images/packer-windoze.yml` pins the fork URL and the exact commit; the script clones
it to `.lab/packer-windoze` and checks out that commit.

## License

Base windows roles are forked from jobrean93/ansible-windows. Keeping the original license as is.
