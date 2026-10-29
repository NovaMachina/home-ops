# OPNsense configuration module.
#
# Resource names below follow the browningluke/opnsense provider. Uncomment
# and adjust as you start codifying real firewall config. Remember to run an
# OPNsense config export / take a snapshot before the first apply.

# resource "opnsense_firewall_filter" "this" {
#   for_each = var.firewall_rules
#
#   enabled     = !each.value.disabled
#   action      = each.value.action
#   interface   = [each.value.interface]
#   direction   = each.value.direction
#   protocol    = each.value.protocol
#   description = coalesce(each.value.description, each.key)
#
#   source = {
#     net  = each.value.source_net
#     port = each.value.source_port
#   }
#
#   destination = {
#     net  = each.value.destination_net
#     port = each.value.destination_port
#   }
# }

# resource "opnsense_dhcp_static_map" "this" {
#   for_each = var.static_dhcp_leases
#
#   subnet      = each.value.subnet
#   mac         = each.value.mac_address
#   ipaddr      = each.value.ip_address
#   hostname    = each.key
#   description = coalesce(each.value.description, each.key)
# }

# resource "opnsense_unbound_host_override" "this" {
#   for_each = var.unbound_host_overrides
#
#   hostname    = each.value.hostname
#   domain      = each.value.domain
#   server      = each.value.server
#   description = coalesce(each.value.description, each.key)
# }
