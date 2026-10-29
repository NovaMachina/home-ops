# terraform

IaC for infrastructure that lives *outside* the Kubernetes cluster:

- **OPNsense** firewall — rules, DHCP static maps, Unbound DNS overrides
- **Proxmox VE** — VMs (cloud-init cloned from templates) *(planned)*

Runs on **OpenTofu** (`tofu`), pinned via `mise`. Terraform >= 1.6 also works.

## Layout

```
terraform/
  versions.tf              provider + version constraints, local backend
  providers.tf             provider config, decrypts secrets.sops.yaml
  variables.tf             endpoints / TLS toggles (non-secret)
  main.tf                  module wiring (currently empty)
  outputs.tf
  secrets.sops.yaml        SOPS-encrypted API credentials (gitignored plaintext)
  secrets.sops.yaml.example
  modules/
    opnsense/              firewall / DHCP / DNS resources
    proxmox-vm/            reusable cloud-init VM
```

## Secrets

Credentials live in `secrets.sops.yaml`, encrypted with the same age key as the
rest of the repo (`.sops.yaml` has a `terraform/**` full-file rule). The
`carlpett/sops` provider decrypts it at plan/apply time using
`SOPS_AGE_KEY_FILE` (`./age.key`, exported by mise).

First-time setup:

```sh
cp secrets.sops.yaml.example secrets.sops.yaml
$EDITOR secrets.sops.yaml          # fill in real values
sops --encrypt --in-place secrets.sops.yaml
```

Later edits: `task terraform:edit-secrets`.

### OPNsense API key
System → Access → Users → (a dedicated `terraform` user) → API keys.

### Proxmox API token
Datacenter → Permissions → API Tokens. Create `terraform@pve!terraform`,
grant it a role with the privileges the bpg/proxmox provider needs
(`PVEVMAdmin` + datastore/SDN as required). Token string form:
`USER@REALM!TOKENID=UUID`.

## Usage

```sh
task terraform:init
task terraform:plan
task terraform:apply
task terraform:fmt
task terraform:validate
```

Or call `tofu` directly from this directory.

## Notes

- State is **local** (`terraform.tfstate`, gitignored) for now. Move to a
  remote backend once an S3-compatible target exists (Rook-Ceph RGW).
- Take an OPNsense config backup / snapshot before the first `apply`.
- Providers: [`browningluke/opnsense`](https://registry.terraform.io/providers/browningluke/opnsense/latest/docs),
  [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs).
