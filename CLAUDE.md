# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Home Kubernetes cluster managed via GitOps. Stack: **Talos Linux** (OS) + **Flux** (GitOps) + **Helm/Kustomize** (manifests) + **SOPS/age** (secrets) + **1Password** (secret backend via external-secrets).

Cluster: 3 Talos controller nodes at `10.0.40.100-102`, VIP `10.0.40.10`. Storage: Rook-Ceph (primary) + OpenEBS. Ingress: Envoy Gateway (internal/external classes). DNS: external-dns + k8s_gateway. TLS: cert-manager.

## Dev Environment

Tools managed by `mise`. Run `mise install` to get everything. Key env vars set automatically by mise:

```
KUBECONFIG=./kubeconfig
SOPS_AGE_KEY_FILE=./age.key
TALOSCONFIG=./talos/clusterconfig/talosconfig
```

Pre-commit hook (lefthook) auto-formats staged YAML files via `yamlfmt`. Never formats `*.sops.yaml`.

## Common Commands

```sh
task reconcile                          # force Flux to sync from git
task kubernetes:sync-externalsecrets    # force sync all ExternalSecrets
task kubernetes:cleanup-pods            # delete Failed/Pending/Succeeded pods

task talos:generate-config              # regenerate Talos configs from talconfig.yaml
task talos:apply-node IP=10.0.40.100 MODE=auto
task talos:upgrade-node IP=10.0.40.100
task talos:upgrade-k8s

task volsync:snapshot APP=<name> NS=<namespace>
task volsync:restore APP=<name> NS=<namespace> PREVIOUS=<snapshot-id>
task volsync:list APP=<name> NS=<namespace>
task volsync:snapshot-all               # snapshot everything, no wait

task postgres:backup                    # manual postgres backup

flux get ks -A                          # check all Kustomizations
flux get hr -A                          # check all HelmReleases
```

## Kubernetes App Structure

Every app follows this layout:

```
kubernetes/apps/<namespace>/<app>/
  ks.yaml            # Flux Kustomization — points to ./app, sets substitutions
  app/
    kustomization.yaml
    helmrelease.yaml   # or plain manifests
    externalsecret.yaml
    ...
```

Namespace-level `kustomization.yaml` lists all `<app>/ks.yaml` entries and applies the `../../components/common` component.

`ks.yaml` pattern: `postBuild.substituteFrom` pulls from `cluster-secrets` Secret; `postBuild.substitute` passes per-app vars (e.g. `APP`, `VOLSYNC_CAPACITY`).

## Secrets

- All secrets encrypted with SOPS+age. Key: `age.key` in repo root (gitignored).
- `.sops.yaml` rules: `talos/**` encrypts full file; `bootstrap/**` and `kubernetes/**` encrypt only `data`/`stringData` keys.
- Runtime secrets pulled from **1Password** via `external-secrets` operator. `ClusterSecretStore` name: `onepassword`. ExternalSecrets reference vault `homelab`.
- Never commit unencrypted `*.sops.yaml` files.

## Adding a New App

1. Create `kubernetes/apps/<namespace>/<app>/ks.yaml` — copy an existing one as template.
2. Create `kubernetes/apps/<namespace>/<app>/app/` with `kustomization.yaml` + `helmrelease.yaml`.
3. Add `- ./<app>/ks.yaml` to `kubernetes/apps/<namespace>/kustomization.yaml`.
4. If app needs persistent storage with backups, add the `volsync` component in `app/kustomization.yaml`.
5. If app needs secrets, add `externalsecret.yaml` referencing `ClusterSecretStore/onepassword`.

## Talos Config

- `talos/talconfig.yaml` — node definitions, image URLs (from factory.talos.dev)
- `talos/talenv.yaml` — `talosVersion` and `kubernetesVersion` (Renovate tracks these)
- `talos/patches/` — global and controller-specific patches
- Regenerate after any change: `task talos:generate-config`
- Apply requires waiting for Ceph health before/after: handled automatically by `task talos:apply-node`

## CI

GitHub Actions runs `flux-local test` and `flux-local diff` on PRs touching `kubernetes/**`. Entry point for flux-local: `kubernetes/flux/cluster`.

Renovate runs weekends, ignores `*.sops.*` files, groups related packages (cert-manager, CoreDNS, Flux Operator, etc.).

## Ingress

Ingress uses **Envoy Gateway** (Kubernetes Gateway API), not ingress-nginx. Any remaining nginx manifests in the repo are stale and pending removal.

GatewayClass: `envoy` (controller: `gateway.envoyproxy.io/gatewayclass-controller`)

Three Gateways in `network` namespace:

| Gateway | Type | LB IP | Hostname pattern |
|---|---|---|---|
| `internal` | internal | `10.0.40.3` | `*.${SECRET_DOMAIN}` |
| `internal-root` | internal | `10.0.40.20` | `${SECRET_DOMAIN}` (apex) |
| `external` | external | `10.0.40.4` | `*.${SECRET_DOMAIN}` |

Apps use `HTTPRoute` resources (not `Ingress`) referencing these Gateways. Use `internal` for private-network-only apps, `external` for public internet exposure.
