terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.8.1"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "3.2.1"
    }
  }
}

provider "onepassword" {
  url = var.OP_CONNECT_HOST
  token = var.OP_CONNECT_TOKEN
}

module "onepassword_authentik" {
  source = "github.com/joryirving/terraform-1password-item"
  vault  = "homelab"
  item   = "authentik"
}

provider "authentik" {
  url   = "https://auth.${var.CLUSTER_DOMAIN}"
  token = module.onepassword_authentik.fields["AUTHENTIK_TOKEN"]
}
