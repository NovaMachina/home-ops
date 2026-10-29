variable "firewall_rules" {
  description = "Map of firewall filter rules keyed by a stable name"
  type = map(object({
    interface        = string           # e.g. "lan", "wan", "opt1"
    direction        = optional(string) # "in" | "out"
    action           = optional(string, "pass")
    protocol         = optional(string, "any")
    source_net       = optional(string, "any")
    source_port      = optional(string)
    destination_net  = optional(string, "any")
    destination_port = optional(string)
    description      = optional(string)
    disabled         = optional(bool, false)
  }))
  default = {}
}

variable "static_dhcp_leases" {
  description = "Map of static DHCP mappings keyed by hostname"
  type = map(object({
    mac_address = string
    ip_address  = string
    subnet      = string # OPNsense interface name for the DHCP scope
    description = optional(string)
  }))
  default = {}
}

variable "unbound_host_overrides" {
  description = "Map of Unbound DNS host overrides keyed by FQDN"
  type = map(object({
    hostname    = string
    domain      = string
    server      = string # target IP
    description = optional(string)
  }))
  default = {}
}
