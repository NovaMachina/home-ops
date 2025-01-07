
data "authentik_group" "admins" {
  name = "authentik Admins"
}

resource "authentik_group" "downloads" {
  name         = "Downloads"
  is_superuser = false
}

resource "authentik_group" "grafana_admin" {
  name         = "Grafana Admin"
  is_superuser = false
}

resource "authentik_group" "headscale" {
  name         = "Headscale"
  is_superuser = false
}

resource "authentik_group" "home" {
  name         = "Home"
  is_superuser = false
}

resource "authentik_group" "infrastructure" {
  name         = "Infrastructure"
  is_superuser = false
}

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}

resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

resource "authentik_policy_binding" "admins" {
  for_each = local.admin_apps
  target   = each.value
  group    = data.authentik_group.admins.id
  order    = 0
}

resource "authentik_policy_binding" "home" {
  for_each = local.household_apps
  target   = each.value
  group    = authentik_group.home.id
  order    = 0
}

resource "authentik_policy_binding" "grafana_admin" {
  target = module.grafana.application_id
  group = authentik_group.grafana_admin.id
  order = 0
}
