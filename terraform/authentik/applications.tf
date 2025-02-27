locals {
  icon_base                   = "https://raw.githubusercontent.com/NovaMachina/home-ops/main/icons"
  implicit_authorization_flow = authentik_flow.provider-authorization-implicit-consent.uuid
  default_authentication_flow = authentik_flow.authentication.uuid
  default_invalidation_flow   = data.authentik_flow.default-provider-invalidation-flow.id

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
  invalidation_flow_uuid  = local.default_invalidation_flow
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
  signing_key            = data.authentik_certificate_key_pair.generated.id
}

module "immich" {
  source                 = "./modules/oidc-application"
  name                   = "immich"
  client_id              = "immich"
  domain                 = "immich.${var.internal_domain}"
  group                  = "Books"
  authorization_flow_id  = local.implicit_authorization_flow
  authentication_flow_id = local.default_authentication_flow
  invalidation_flow_id   = local.default_invalidation_flow
  redirect_uris          = ["https://immich.${var.internal_domain}/auth/login"]
  property_mappings      = data.authentik_property_mapping_provider_scope.oauth2.ids
  access_token_validity  = "hours=4"
  authentik_domain       = var.authentik_domain
  vault                  = local.onepassword_vault_id
  meta_icon              = "${local.icon_base}/immich.png"
  signing_key            = data.authentik_certificate_key_pair.generated.id
}

module "home-assistant" {
  source                  = "./modules/forward-auth-application"
  name                    = "home-assistant"
  domain                  = "hass.${var.internal_domain}"
  group                   = "Books"
  authorization_flow_uuid = local.implicit_authorization_flow
  invalidation_flow_uuid  = local.default_invalidation_flow
  meta_icon               = "${local.icon_base}/home-assistant.png"
}

module "paperless" {
  source                 = "./modules/oidc-application"
  name                   = "paperless"
  client_id              = "paperless"
  domain                 = "paperless.${var.internal_domain}"
  group                  = "Books"
  authorization_flow_id  = local.implicit_authorization_flow
  authentication_flow_id = local.default_authentication_flow
  invalidation_flow_id   = local.default_invalidation_flow
  redirect_uris          = ["https://paperless.${var.internal_domain}/accounts/oidc/authentik/login/callback/"]
  property_mappings      = data.authentik_property_mapping_provider_scope.oauth2.ids
  access_token_validity  = "hours=4"
  authentik_domain       = var.authentik_domain
  vault                  = local.onepassword_vault_id
  meta_icon              = "${local.icon_base}/grafana.png"
  signing_key            = data.authentik_certificate_key_pair.generated.id
}
