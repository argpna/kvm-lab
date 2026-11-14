variable "host_file" {
  description = "Path to the JSON written by inventory/inventory.py --host <name>."
  type        = string
}

variable "base_volume" {
  description = "File name of the base image in the lab-base pool."
  type        = string
}

variable "repo_root" {
  description = "Absolute path of the repo root (source of the sync_folders host_path '.')."
  type        = string
}

variable "ssh_pubkey_file" {
  description = "Path to the lab SSH public key installed for the lab user on Linux guests."
  type        = string
}

variable "lab_user" {
  description = "Account created on Linux guests for Ansible (lab_user in credentials.yml)."
  type        = string
}

variable "base_pool" {
  type    = string
  default = "lab-base"
}

variable "vm_pool" {
  type    = string
  default = "lab-vms"
}
