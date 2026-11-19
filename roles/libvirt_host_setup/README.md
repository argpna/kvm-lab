# Ansible libvirt_host_setup role

## Overview

The role prepares the machine that runs the lab. The role installs QEMU, libvirt, the libguestfs
tools, OVMF, nftables, and client tools, starts the libvirt daemons, adds the user to the `libvirt`
group, creates the storage pools, and installs OpenTofu into `/usr/local/bin`.

## Variables

### Mandatory variables

None.

### Optional variables

* `libvirt_host_setup_user`: User added to the group `libvirt`. Default: the user running Ansible.
* `libvirt_host_setup_require_kvm`: Fail when `/dev/kvm` does not exist. Default: `true`.
* `libvirt_host_setup_virsh_uri`: libvirt URI that the pool tasks connect to.
  Default: `qemu:///system`.
* `libvirt_host_setup_pools`: Directory pools to create, as a list of `name` and `path`.
  Default: `lab-base` and `lab-vms` under `/var/lib/libvirt/images`.
* `libvirt_host_setup_tofu_version`: OpenTofu version to install. The role verifies the download
  against the published SHA256 sums. Default: `1.13.9`.
* `libvirt_host_setup_tofu_dir`: Directory that receives the `tofu` binary. Default: `/usr/local/bin`.

### Role variables

The role sets the following variables for each OS family in `vars/Debian.yml` and `vars/RedHat.yml`:

* `libvirt_host_setup_packages`: Packages to install.
* `libvirt_host_setup_sockets`: libvirt systemd sockets to enable and start on dnf hosts.
* `libvirt_host_setup_services`: libvirt systemd services to enable and start on apt hosts.

## Tags

The role has the tags `packages`, `services`, `access`, `pools`, and `tofu`. The checks at the start
of the role run with every tag.

## Example

```yml
- name: set up this machine as a lab host
  hosts: localhost
  connection: local
  gather_facts: true
  gather_subset: [min]
  roles:
    - role: libvirt_host_setup
      vars:
        libvirt_host_setup_tofu_version: "1.13.9"
```