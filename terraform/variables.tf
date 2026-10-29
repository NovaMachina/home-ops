variable "opnsense_uri" {
  description = "Base URL of the OPNsense API, e.g. https://10.0.40.1"
  type        = string
  default     = "https://10.0.40.1"
}

variable "proxmox_endpoint" {
  description = "Base URL of the Proxmox VE API, e.g. https://10.0.40.2:8006"
  type        = string
  default     = "https://10.0.40.2:8006"
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API (self-signed cert)"
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "SSH user on the Proxmox node for operations that require it"
  type        = string
  default     = "root"
}
