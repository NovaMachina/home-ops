provider "authentik" {}

provider "onepassword" {
  url = "https://op.jacob-williams.me"
  # token specified via env var
}

resource "authentik_service_connection_kubernetes" "remote-cluster" {
  name       = "remote"
  verify_ssl = false
  kubeconfig = jsonencode(yamldecode(data.local_file.kubeconfig.content))
}

data "sops_file" "secrets" {
  source_file = "../secrets.sops.yaml"
}

data "local_file" "kubeconfig" {
  filename = "../../kubeconfig"
}

locals {
  secrets               = yamldecode(data.sops_file.secrets.raw)
  onepassword_vault_id  = local.secrets.onepassword_vault_id
}
