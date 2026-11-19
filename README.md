# kvm-lab

Linux and Windows lab VMs on KVM and libvirt, configured by Ansible. OpenTofu creates each VM with
the `dmacvicar/libvirt` provider and keeps one state file per host. Each VM boots from a base image
stored in a libvirt pool.

## Requirements

- An x86_64 Linux host with a dnf or apt package manager (Fedora, Debian, Ubuntu).
- Hardware virtualization enabled, so that `/dev/kvm` exists.
- Python 3.

`lab host-setup` installs QEMU, libvirt, the libguestfs tools, OVMF (UEFI firmware), nftables, and
`jq`, creates the libvirt pools `lab-base` and `lab-vms`, and installs OpenTofu in
`/usr/local/bin/tofu`.

The lab commands that change libvirt networks also run `sudo`, setting up passwordless `sudo` is
recommended.

## Get started

1. Create the virtual environment with `bootstrap/setup-host-venv.sh`, and activate the virtual
   environment with `source .venv/bin/activate`.
2. Install the host prerequisites with `lab host-setup`. Add `--check` to preview the changes, or
   add `--ask-become-pass` if `sudo` needs a password.
3. Build the base images with `lab image build [image-name]`.
4. Create the VMs with `lab up [vm-name]`.
5. Configure the VMs with `lab provision [vm-name]`.

## Usage

Run the commands through `lab` (`scripts/lab`), which is on the `PATH` once the virtual environment
is activated.

| Command | Action |
| --- | --- |
| `lab host-setup [args]` | Install and configure the host prerequisites. The command passes `args` to `ansible-playbook`. |
| `lab image build [--force] [name ...]` | Download the Linux images in `images/linux.yml` and build the Windows images in `images/windows.yml`. |
| `lab image list` | List the base images. |
| `lab image prune [--delete]` | List old base images that no disk uses. With `--delete`, the command deletes the old base images. |
| `lab up [limit]` | Create the VMs, and wait until the VMs accept connections. |
| `lab provision [limit] [args]` | Run `playbooks/main.yml`. The command passes `args` to `ansible-playbook`. |
| `lab stop [limit] [--force]` | Shut the VMs down. With `--force`, the command powers the VMs off. |
| `lab destroy [limit] [--force]` | Delete the VMs. With `--force`, the command skips the confirmation. |
| `lab status` | List the lab VMs. |
| `lab hosts` | List the inventory hosts and groups. |

### Limits

A limit is an Ansible host pattern: a host, a group, `host1,host2`, or a wildcard pattern. Run
`lab hosts` to list the inventory hosts. When the limit is omitted, `up`, `provision`, `stop`, and
`destroy` apply to all hosts.

## Base images

A base image is a read-only qcow2 file named `<image>-<YYYYMMDDHHMM>.qcow2` in the `lab-base`
libvirt pool (`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest file
whose name starts with that image name. The VM disks and cloud-init seed ISOs are stored in the
`lab-vms` pool.

To build every image in the manifests, run `lab image build`. To build selected images, run
`lab image build ubuntu-22.04 windows-2022`, for example. The Linux images are the vendor cloud
images listed in `images/linux.yml`. The Windows images are built from the Microsoft evaluation VHDs
listed in `images/windows.yml`.

After each build, the command saves a checksum of the inputs that the image was built from in
`.lab/images/`. For a Linux image, the checksum covers the download URL and hash in
`images/linux.yml`. For a Windows image, the checksum covers the entries in `images/windows.yml` and
the files in `images/windows/`. On the next run, the command skips an image when the checksum is
unchanged since the command built the newest file for that image. If the checksum has changed, or if
you pass `--force`, the command builds a new image file.

Run `lab image prune` to list old images that no VM uses. Pass `--delete` with `lab image prune` to
delete the old image files.

If you delete `.lab/images/`, the next `lab image build` rebuilds every image again. Downloads are
cached in `~/.cache/kvm-lab`.

## License

The base Windows roles are forked from jobrean93/ansible-windows. The project retains the original
MIT license, with copyright held by Jordan Borean, in the `LICENSE` file.