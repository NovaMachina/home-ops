resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

resource "authentik_group" "admins" {
  name         = "Admins"
  is_superuser = true
}

resource "authentik_group" "books" {
  name         = "Books"
  is_superuser = false
}

resource "authentik_group" "home" {
  name         = "Home"
  is_superuser = false
}

resource "authentik_policy_binding" "admins" {
  for_each = local.admin_apps
  target   = each.value
  group    = authentik_group.admins.id
  order    = 0
}

resource "authentik_policy_binding" "home" {
  for_each = local.household_apps
  target   = each.value
  group    = authentik_group.home.id
  order    = 0
}
