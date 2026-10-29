# output "firewall_rule_ids" {
#   value = { for k, r in opnsense_firewall_filter.this : k => r.id }
# }

output "lan_interface" {
  value = data.opnsense_interface.lan
}
