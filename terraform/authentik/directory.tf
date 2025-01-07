# Step 1: Retrieve secrets from 1Password
module "onepassword_application" {
  source   = "github.com/joryirving/terraform-1password-item"
  vault    = "homelab"
  item     = "actual"
}

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

resource "authentik_group" "finance" {
  name = "finance"
  is_superuser = false
  attributes = jsonencode({
    "additionalHeaders": {
        "x-actual-password": module.onepassword_application.fields["password"]
    }
  })
}

resource "authentik_policy_binding" "grafana_admin" {
  target = module.grafana.application_id
  group = authentik_group.grafana_admin.id
  order = 0
}

resource "authentik_policy_binding" "actual" {
  target = module.actual-budget.application_id
  group = authentik_group.finance.id
  order = 0
}
