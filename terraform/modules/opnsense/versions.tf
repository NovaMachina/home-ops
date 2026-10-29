terraform {
  required_version = ">= 1.12.0"

  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = ">= 0.26.0"
    }
  }
}
