# Wire modules here as configuration grows.
#
module "firewall" {
  source = "./modules/opnsense"

  # ...inputs
}
#
# module "vm_example" {
#   source = "./modules/proxmox-vm"
#
#   name      = "example"
#   node_name = "pve"
#   # ...inputs
# }

# One-shot imports of the existing OPNsense VLAN interfaces into the
# firewall module. Safe to delete once `tofu apply` has run and state is
# populated.
