# Expose useful attributes from modules here as they are added.

output "lan_interface" {
  value = module.firewall.lan_interface
}
