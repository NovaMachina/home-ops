
locals {
  icon_base                   = "https://raw.githubusercontent.com/NovaMachina/home-ops/main/icons"
  implicit_authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  explicit_authorization_flow = data.authentik_flow.default-provider-authorization-explicit-consent.id
  default_authentication_flow = data.authentik_flow.default-authentication-flow.id
  default_invalidation_flow   = data.authentik_flow.default-invalidation-flow.id

  admin_apps = {
    "grafana" = module.grafana.application_id,
  }

  household_apps = {
    "actual-budget" = module.actual-budget.application_id
  }
}

module "actual-budget" {
  source                  = "./modules/forward-auth-application"
  name                    = "actual-budget"
  domain                  = "actual.${var.external_domain}"
  group                   = "Home"
  authorization_flow_uuid = local.implicit_authorization_flow
  invalidation_flow_id    = local.default_invalidation_flow
  meta_icon               = "${local.icon_base}/actual.png"
}

module "grafana" {
  source                 = "./modules/oidc-application"
  name                   = "grafana"
  client_id              = "grafana"
  domain                 = "grafana.${var.internal_domain}"
  group                  = "Books"
  authorization_flow_id  = local.implicit_authorization_flow
  authentication_flow_id = local.default_authentication_flow
  invalidation_flow_id   = local.default_invalidation_flow
  redirect_uris          = ["https://grafana.${var.internal_domain}/login/generic_oauth"]
  property_mappings      = data.authentik_property_mapping_provider_scope.oauth2.ids
  access_token_validity  = "hours=4"
  authentik_domain       = var.authentik_domain
  vault                  = local.onepassword_vault_id
  meta_icon              = "${local.icon_base}/grafana.png"
}

module "immich" {
  source                 = "./modules/oidc-application"
  name                   = "immich-test"
  client_id              = "immich-test"
  domain                 = "immich-test.${var.internal_domain}"
  group                  = "Books"
  authorization_flow_id  = local.explicit_authorization_flow
  authentication_flow_id = local.default_authentication_flow
  invalidation_flow_id   = local.default_invalidation_flow
  redirect_uris          = ["https://immich-test.${var.internal_domain}/auth/login"]
  property_mappings      = data.authentik_property_mapping_provider_scope.oauth2.ids
  access_token_validity  = "hours=4"
  authentik_domain       = var.authentik_domain
  vault                  = local.onepassword_vault_id
  meta_icon              = "${local.icon_base}/immich.png"
}

module "home-assistant" {
  source                  = "./modules/forward-auth-application"
  name                    = "home-assistant"
  domain                  = "hass.${var.internal_domain}"
  group                   = "Books"
  authorization_flow_uuid = local.implicit_authorization_flow
  invalidation_flow_id    = local.default_invalidation_flow
  meta_icon               = "${local.icon_base}/immich.png"
}
