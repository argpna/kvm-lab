# kvm-lab

Linux and Windows lab VMs on KVM and libvirt, configured by Ansible. OpenTofu creates each VM with
the `dmacvicar/libvirt` provider and keeps one state file per host. Each VM boots from a base image
stored in a libvirt pool.

## Requirements

- A Linux host with libvirt, QEMU, KVM (Kernel-based Virtual Machine), `jq`, and passwordless `sudo`
- Python 3, to create the virtual environment
- The OpenTofu binary at `.venv/bin/tofu`. `bootstrap/setup-host-venv.sh` does not install it, but it
  keeps an existing binary when it recreates the environment.

## Get started

1. Create the virtual environment: `bootstrap/setup-host-venv.sh` and activate it
   `source .venv/bin/activate`
2. Build the base images: `lab image build [image-name]`
3. Create the VMs: `lab up [vm-name]`
4. Configure them: `lab provision [vm-name]`

## Usage

Run the commands through `lab` (`scripts/lab`), which is on the `PATH` once the virtual environment
is activated.

| Command | Action |
| --- | --- |
| `lab image build [--force] [name ...]` | Download the Linux images in `images/linux.yml` and build the Windows images in `images/windows.yml`. |
| `lab image list` | List the base images. |
| `lab image prune [--delete]` | List old base images that no disk uses. With `--delete`, delete them. |
| `lab up [limit]` | Create the VMs and wait until they accept connections. |
| `lab provision [limit] [args]` | Run `playbooks/main.yml`. The command passes `args` to `ansible-playbook`. |
| `lab stop [limit] [--force]` | Shut the VMs down. With `--force`, power them off. |
| `lab destroy [limit] [--force]` | Delete the VMs. With `--force`, skip the confirmation. |
| `lab status` | List the lab VMs. |
| `lab hosts` | List the inventory hosts and groups. |

### Limits

A limit is an Ansible host pattern: a host, a group, `host1,host2`, or a wildcard pattern. Run
`lab hosts` to list the inventory hosts. When the limit is omitted, `up`, `provision`, `stop` and
`destroy` apply to all hosts.

## Base images

A base image is a read-only qcow2 file named `<image>-<YYYYMMDDHHMM>.qcow2` in the `lab-base`
libvirt pool (`/var/lib/libvirt/images/lab-base`). The `image` key of a host selects the newest file
whose name starts with that image name. The VM disks and cloud-init seed ISOs are stored in the
`lab-vms` pool.

To build every image in the manifests, run `lab image build`. To build the images selectively,
for example, run `lab image build ubuntu-22.04 windows-2022`. The Linux images are the vendor cloud images
listed in `images/linux.yml`. The Windows images are built from the Microsoft evaluation VHDs listed
in `images/windows.yml`.

After each build, the command saves a checksum of what the image was built from in `.lab/images/`.
For a Linux image, it is the download URL and hash in `images/linux.yml`. For a Windows image,
it is the entries in `images/windows.yml` and the files in `images/windows/`. On the next run, the
command skips an image when the checksum is unchanged since its newest file was built. If there is a
checksum mismatch, or `--force` is passed, the command builds a new image file.

Run `lab image prune` to list old images that are not in use by any VMs. Pass `--delete` with prune
to clean up the old image files.

If `.lab/images/` is deleted, the next `lab image build` rebuilds every image again. Downloads are
cached in `~/.cache/kvm-lab`.

## License

The base Windows roles are forked from jobrean93/ansible-windows. The project retains the original
MIT license, with copyright held by Jordan Borean, in the `LICENSE` file.