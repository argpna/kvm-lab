locals {
  h          = jsondecode(file(var.host_file))
  name       = local.h.inventory_hostname
  is_windows = local.h.os == "windows"

  allowed_options = ["cpus", "memory_mb", "cpu_mode", "nic_model", "video_type", "graphics", "memory_backing", "sync_folders", "disk_gb"]
  po              = local.h.provider_options

  cpus           = try(local.po.cpus, 2)
  memory_mb      = try(local.po.memory_mb, 2048)
  cpu_mode       = try(local.po.cpu_mode, "host-model")
  nic_model      = try(local.po.nic_model, "virtio")
  video_type     = try(local.po.video_type, local.is_windows ? "qxl" : "virtio")
  graphics_type  = try(local.po.graphics.type, local.is_windows ? "spice" : "vnc")
  memory_backing = lower(try(local.po.memory_backing, "off"))
  disk_gb        = try(local.po.disk_gb, local.is_windows ? 40 : 20)
  sync_folders = [
    for i, s in try(local.po.sync_folders, []) : s
    if try(s.enabled, false) && try(s.type, "disabled") == "virtiofs"
  ]

  nics = [
    for n in local.h.interfaces.attached : one([
      for d in local.h.interfaces.declared : d if d.name == n
    ])
  ]
  connection_nic = local.h.interfaces.connection

  pubkey = trimspace(file(var.ssh_pubkey_file))
  bootstrap = try(local.h.bootstrap_python, null)
  install_cmd = {
    apt    = "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y"
    dnf    = "dnf install -y"
    zypper = "zypper --non-interactive install -y"
  }

  user_data = <<-EOT
    #cloud-config
    hostname: ${local.name}
    manage_etc_hosts: true
    package_update: false
    users:
      - name: vagrant
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${local.pubkey}
    %{~ if length(local.sync_folders) > 0 }
    mounts:
    %{~ for s in local.sync_folders }
      - [repo${index(local.sync_folders, s)}, ${s.guest_path}, virtiofs, "defaults,nofail", "0", "0"]
    %{~ endfor }
    %{~ endif }
    %{~ if local.bootstrap != null }
    runcmd:
      - [sh, -c, "test -x ${local.h.ansible_python_interpreter} || { ${local.install_cmd[local.bootstrap.manager]} ${local.bootstrap.package} && ${try(local.bootstrap.post, "true")}; }"]
    %{~ endif }
  EOT

  network_config = yamlencode({
    version = 2
    ethernets = {
      for n in local.nics : n.name => {
        match = { macaddress = n.mac }
        "set-name" = n.name
        dhcp4      = true
        "dhcp4-overrides" = { "use-routes" = n.name == local.connection_nic }
      }
    }
  })
}

check "provider_options_known" {
  assert {
    condition     = length(setsubtract(keys(local.po), local.allowed_options)) == 0
    error_message = "Host ${local.name}: unsupported provider_options keys: ${join(", ", setsubtract(keys(local.po), local.allowed_options))}"
  }
}

check "memory_backing_valid" {
  assert {
    condition     = contains(["off", "shared", "memfd"], local.memory_backing)
    error_message = "Host ${local.name}: provider_options.memory_backing must be off, shared or memfd"
  }
}

check "virtiofs_needs_shared_memory" {
  assert {
    condition     = length(local.sync_folders) == 0 || local.memory_backing != "off"
    error_message = "Host ${local.name}: sync_folders (virtiofs) require memory_backing shared or memfd"
  }
}

resource "libvirt_cloudinit_disk" "seed" {
  count          = local.is_windows ? 0 : 1
  name           = "lab-${local.name}-seed"
  meta_data      = "instance-id: lab-${local.name}\nlocal-hostname: ${local.name}\n"
  user_data      = local.user_data
  network_config = local.network_config
}

resource "libvirt_volume" "seed" {
  count  = local.is_windows ? 0 : 1
  name   = "lab-${local.name}-seed.iso"
  pool   = var.vm_pool
  create = { content = { url = libvirt_cloudinit_disk.seed[0].path } }
}

resource "libvirt_volume" "root" {
  name          = "lab-${local.name}.qcow2"
  pool          = var.vm_pool
  capacity      = local.disk_gb
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }
  backing_store = {
    path   = "/var/lib/libvirt/images/${var.base_pool}/${var.base_volume}"
    format = { type = "qcow2" }
  }
}

resource "libvirt_domain" "vm" {
  name        = "lab-${local.name}"
  type        = "kvm"
  memory      = local.memory_mb
  memory_unit = "MiB"
  vcpu        = local.cpus
  running     = true

  os  = { type = "hvm", type_arch = "x86_64", type_machine = "pc" }
  cpu = { mode = local.cpu_mode }

  clock = {
    offset = local.is_windows ? "localtime" : "utc"
    timer  = local.is_windows ? [{ name = "hypervclock", present = "yes" }] : []
  }

  features = {
    acpi = true
    apic = {}
    pae  = true
    hyper_v = local.is_windows ? {
      mode      = "custom"
      relaxed   = { state = "on" }
      vapic     = { state = "on" }
      spinlocks = { state = "on", retries = 8191 }
    } : null
  }

  memory_backing = local.memory_backing == "off" ? null : {
    memory_access = { mode = "shared" }
    memory_source = local.memory_backing == "memfd" ? { type = "memfd" } : null
  }

  devices = {
    disks = concat(
      [{
        device    = "disk"
        read_only = false
        driver    = { name = "qemu", type = "qcow2" }
        source = { volume = { pool = libvirt_volume.root.pool, volume = libvirt_volume.root.name } }
        target = { dev = "vda", bus = "virtio" }
      }],
      local.is_windows ? [] : [{
        device    = "disk"
        read_only = true
        driver    = { name = "qemu", type = "raw" }
        source    = { volume = { pool = libvirt_volume.seed[0].pool, volume = libvirt_volume.seed[0].name } }
        target    = { dev = "vdb", bus = "virtio" }
      }]
    )
    interfaces = [
      for n in local.nics : {
        mac    = { address = n.mac }
        model  = { type = local.nic_model }
        source = { network = { network = n.network } }
      }
    ]
    filesystems = [
      for i, s in local.sync_folders : {
        driver      = { type = "virtiofs" }
        access_mode = "passthrough"
        read_only   = try(s.readonly, false)
        source      = { mount = { dir = s.host_path == "." ? var.repo_root : s.host_path } }
        target      = { dir = "repo${i}" }
      }
    ]
    serials = local.is_windows ? [] : [{
      source = { file = { path = "/var/log/libvirt/qemu/lab-${local.name}-serial.log" } }
      target = { type = "isa-serial", port = 0 }
    }]
    controllers = local.is_windows ? [{ type = "usb", index = 0, model = "qemu-xhci" }] : []
    inputs      = local.is_windows ? [{ type = "tablet", bus = "usb" }] : []
    videos = [{
      model = {
        type    = local.video_type
        ram     = local.video_type == "qxl" ? 65536 : null
        vram    = local.video_type == "qxl" ? 16384 : null
        vga_mem = local.video_type == "qxl" ? 16384 : null
        heads   = local.video_type == "qxl" ? 1 : null
        primary = local.video_type == "qxl" ? "yes" : null
      }
    }]
    graphics = [{
      spice = local.graphics_type == "spice" ? { auto_port = true, listen = "127.0.0.1" } : null
      vnc   = local.graphics_type == "vnc" ? { auto_port = true, listen = "127.0.0.1" } : null
    }]
    mem_balloon = { model = "virtio" }
  }
}
