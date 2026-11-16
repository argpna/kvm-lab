# kvm-lab

Linux and Windows lab VMs on KVM/libvirt, configured by Ansible. VMs are created with OpenTofu
(`dmacvicar/libvirt` provider), one state file per host, from base images stored in a libvirt pool.

## Requirements

- A Linux host with libvirt, QEMU/KVM, `jq` and passwordless `sudo`
- Python 3 (for the venv created by `bootstrap/setup-host-venv.sh`)
- OpenTofu in `.venv/bin/tofu`

## Usage

Hosts are selected with `GROUP=<group|host1,host2|pattern>` (any Ansible limit pattern). Default is all hosts.

    make up GROUP=ubuntu2204-sql2022         create the VM and wait until it accepts connections
    make provision GROUP=ubuntu2204-sql2022  run playbooks/main.yml on the host
    make destroy GROUP=ubuntu2204-sql2022    delete the VM
    make status                              list lab VMs

`make up` ensures the libvirt networks used by the selected hosts, creates the VMs in parallel
(`JOBS`, default 4), waits for SSH or PSRP, and renames Windows hosts to their inventory name.


## Base images

Base images are read-only qcow2 files named `<image>-<date>.qcow2` in the `lab-base` libvirt pool
(`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest matching file.
Per-VM disks and cloud-init seed ISOs live in the `lab-vms` pool.
Never boot a base image directly: only overlays of it are booted.

Build the images with `make images-linux` (downloads the cloud images in `images/manifest.yml`) and
`make image-win2022` (builds a Windows image, 1 to 3 hours). The Windows build uses a fork of
packer-windoze. `images/packer-windoze.yml` pins the fork URL and the exact commit; the script clones
it to `.lab/packer-windoze` and checks out that commit. packer-windoze has no licence, so its files are
not copied into this repo.

`lab-base` is not backed up. Linux images are downloaded again with `make images-linux`. A lost Windows
image is rebuilt with `make image-win2022`, which takes 1 to 3 hours.
