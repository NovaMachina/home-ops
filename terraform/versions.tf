terraform {
  # Works with OpenTofu >= 1.6 or Terraform >= 1.6
  required_version = ">= 1.12.0"

  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4.1"
    }
  }

  # backend "local" {
  #   path = "./terraform.tfstate"
  # }

  backend "s3" {
    bucket = "terraform-state"
    key = "home-ops/terraform.tfstate"

    endpoints = {
      s3 = "http://10.0.0.14:30188"
    }
    region = "garage"

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true

    use_lockfile = true
  }
}
