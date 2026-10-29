variable "name" {
  description = "VM name (also used as the hostname)"
  type        = string
}

variable "node_name" {
  description = "Proxmox node to place the VM on"
  type        = string
}

variable "vm_id" {
  description = "Explicit VMID; null lets Proxmox assign one"
  type        = number
  default     = null
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI"
  type        = string
  default     = "Managed by OpenTofu"
}

variable "tags" {
  description = "Tags to apply to the VM"
  type        = list(string)
  default     = ["terraform"]
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size_gb" {
  type    = number
  default = 32
}

variable "datastore_id" {
  description = "Datastore for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge for the primary NIC"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the primary NIC; null for untagged"
  type        = number
  default     = null
}

variable "clone_template_id" {
  description = "VMID of the template to clone from"
  type        = number
}

variable "ip_config" {
  description = "cloud-init IP config; use \"dhcp\" or a CIDR + gateway"
  type = object({
    address = optional(string, "dhcp") # "dhcp" or "10.0.40.50/24"
    gateway = optional(string)
  })
  default = {}
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "ci_user" {
  description = "cloud-init default user"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = "SSH public keys granted to the cloud-init user"
  type        = list(string)
  default     = []
}

variable "started" {
  description = "Whether the VM should be running"
  type        = bool
  default     = true
}
