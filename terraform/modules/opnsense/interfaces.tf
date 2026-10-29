# VLAN interfaces on the OPNsense firewall.
# Imported from the running config on 2026-09-07 (see root main.tf import blocks).
# Parent NIC igc1; device names are provider-computed as vlan0.<tag>.

data "opnsense_interface" "lan" {
  device = "igc1"
}

resource "opnsense_interfaces_vlan" "internal" {
  description = "INTERNAL"
  device      = "vlan0.100"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 100
}

resource "opnsense_interfaces_vlan" "office" {
  description = "OFFICE"
  device      = "vlan0.200"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 200
}

resource "opnsense_interfaces_vlan" "camera" {
  description = "CAMERA"
  device      = "vlan0.300"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 300
}

resource "opnsense_interfaces_vlan" "virtual_machines" {
  description = "VIRTUAL MACHINES"
  device      = "vlan0.400"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 400
}

resource "opnsense_interfaces_vlan" "iot" {
  description = "IOT"
  device      = "vlan0.500"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 500
}

resource "opnsense_interfaces_vlan" "guest" {
  description = "GUEST"
  device      = "vlan0.600"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 600
}

resource "opnsense_interfaces_vlan" "management" {
  description = "MANAGEMENT"
  device      = "vlan0.700"
  parent      = data.opnsense_interface.lan.device
  priority    = 0
  tag         = 700
}
