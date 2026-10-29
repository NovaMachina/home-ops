# Decrypt secrets.sops.yaml at plan/apply time using the repo's age key
# (SOPS_AGE_KEY_FILE is exported by mise -> ./age.key).
data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.sops.yaml"
}

locals {
  secrets = yamldecode(data.sops_file.secrets.raw)
}

provider "opnsense" {
  uri            = var.opnsense_uri
  api_key        = local.secrets["opnsense"]["api_key"]
  api_secret     = local.secrets["opnsense"]["api_secret"]
  allow_insecure = true
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.secrets["proxmox"]["api_token"]
  insecure  = var.proxmox_insecure

  # Some resources (file uploads, VM clones) need SSH to the PVE node.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
