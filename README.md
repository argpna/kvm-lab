# kvm-lab

Linux and Windows lab VMs on KVM/libvirt, configured by Ansible. VMs are created with OpenTofu
(`dmacvicar/libvirt` provider), one state file per host, from base images stored in a libvirt pool.

Status: work in progress. Image build targets are not implemented yet.

## Requirements

- Fedora or another Linux host with libvirt (`qemu:///system`), QEMU/KVM, `jq` and passwordless `sudo`
- Python 3 (for the venv created by `bootstrap/setup-host-venv.sh`)
- OpenTofu in `.venv/bin/tofu`

## Usage

Hosts are selected with `GROUP=<group|host1,host2|pattern>` (any Ansible limit pattern). Default is all hosts.

    make up GROUP=ubuntu2204-sql2022       create the VM and wait until it accepts connections
    make provision GROUP=ubuntu2204-sql2022  run playbooks/main.yml on the host
    make destroy GROUP=ubuntu2204-sql2022  delete the VM
    make status                            list lab VMs

`make up` ensures the libvirt networks used by the selected hosts, creates the VMs in parallel
(`JOBS`, default 4), waits for SSH or PSRP, and renames Windows hosts to their inventory name.

## Layout

    Makefile            user entry point
    scripts/lab-vm.sh   create or destroy one host with OpenTofu
    tofu/               OpenTofu configuration for one host
    images/             image manifest
    inventory/          inventory.py is the single source of host data
    playbooks/ roles/   Ansible

## Base images

Base images are read-only qcow2 files named `<image>-<date>.qcow2` in the `lab-base` libvirt pool
(`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest matching file.
Per-VM disks and cloud-init seed ISOs live in the `lab-vms` pool.
Never boot a base image directly: only overlays of it are booted.
