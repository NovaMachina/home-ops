# home-ops cluster spec

Feature specs: [volsync](specs/volsync.spec.md) | [security](specs/security.spec.md) | [observability-migration](specs/observability-migration.spec.md) | [talos-migration](specs/talos-migration.spec.md) | [justfile-migration](specs/justfile-migration.spec.md) | [adguard-dns](specs/adguard-dns.spec.md)

## §G — Goal

GitOps-managed home Kubernetes cluster. Self-healing, backed up, secret-safe, consistently structured.

---

## §C — Constraints

- Talos Linux nodes; no SSH; config changes via `talconfig.yaml` (talhelper) — migration to raw configs planned (→ T19)
- Flux GitOps; all state in git; no out-of-band kubectl edits
- SOPS+age secrets; `*.sops.yaml` never committed unencrypted
- Runtime secrets via 1Password → external-secrets; `ClusterSecretStore: onepassword`
- Ceph primary storage; VolSync backs up PVCs to MinIO
- Ingress via Envoy Gateway + HTTPRoute; `kind: Ingress` ⊥
- `mise` manages tooling; `lefthook` auto-formats staged YAML (never `*.sops.yaml`)

---

## §I — Interfaces

```
api: Flux reconcile  → git HEAD applied to cluster
api: SOPS decrypt    → age.key (gitignored, repo root)
api: secret runtime  → ClusterSecretStore/onepassword vault:homelab
env: KUBECONFIG      ! ./kubeconfig
env: SOPS_AGE_KEY_FILE ! ./age.key
env: TALOSCONFIG     ! ./talos/clusterconfig/talosconfig
```

---

## §V — Invariants

### Structure

```
V1:  ∀ app → kubernetes/apps/<ns>/<app>/{ks.yaml, app/kustomization.yaml}
V2:  ∀ ns  → kustomization.yaml lists ∀ <app>/ks.yaml & applies ../../components/common
V3:  ∀ app with PVC on ceph-block ≥ critical → volsync component ∈ app/kustomization.yaml
V4:  kind: Ingress ⊥ — use HTTPRoute only
```

### HelmRelease

```
V5:  ∀ HelmRelease → install.remediation.retries: -1
V6:  ∀ HelmRelease → upgrade.cleanupOnFail: true & upgrade.remediation.strategy: rollback
V7:  ∀ HelmRelease → driftDetection.mode: enabled
V8:  cpu limits ⊥ — use requests only (limits → throttle, not protection)
V9:  ∀ container image → pinned tag | SHA; mutable tags (latest, master) ⊥
V10: ∀ schema comment → placed after --- separator
V11: ∀ bjw-s app-template schema URL → org must be bjw-s-labs (not bjw-s)
```

### Kustomization

```
V12: ∀ ks.yaml → retryInterval: 2m alongside interval
V13: ∀ ks.yaml → healthChecks defined for Deployment|StatefulSet|DaemonSet resources
V14: ∀ VOLSYNC_CLAIM override ≠ APP value → comment explaining divergence
```

### Secrets

```
V15: ∀ ExternalSecret → refreshInterval: 5m
V16: REDIS_PASSWORD ∈ immich ExternalSecret | immich uses DB 0 & dragonfly auth disabled — explicit, not commented out
```

### Security

```
V17: privileged: true | runAsUser: 0 → requires inline comment citing hardware requirement
V18: pgAdmin runs as uid 5050 via PGADMIN_UID (⊥ root)
V19: lounge initContainer ⊥ — fsGroup handles ownership; busybox:latest removed
V20: pgAdmin security headers: X_XSS_PROTECTION, ENHANCED_COOKIE_PROTECTION, X_CONTENT_TYPE_OPTIONS ⊥ disabled
```

### Credentials

```
V21: FLOOD_OPTION_QBPASS ≠ "dummy" — secret ref from flood-secret
```

---

## §T — Tasks

| id | status | task | cites |
|----|--------|------|-------|
| T1 | . | Add remediation blocks to ∀ HelmRelease missing them (external-secrets, onepassword-connect, cloudnative-pg, downloads/*, monitoring/*) | V5,V6 |
| T2 | . | Remove cpu limits from dragonfly & rook-ceph cluster (mon, osd, mgr daemons) | V8 |
| T3 | . | Fix flood credentials — uncomment envFrom secret ref, remove FLOOD_OPTION_QBPASS dummy value | V21 |
| T4 | . | Add driftDetection: mode: enabled to ∀ HelmRelease | V7 |
| T5 | . | Add retryInterval: 2m to external-secrets, onepassword-connect, rook-ceph, openebs, downloads/* ks.yaml | V12 |
| T6 | . | Add healthChecks to external-secrets, cloudnative-pg, cilium, downloads/* ks.yaml | V13 |
| T7 | . | Add refreshInterval: 5m to 8 ExternalSecrets (authentik, cloudnative-pg, dragonfly, immich, jellyseerr, harbor, actions-runner, dashboard) | V15 |
| T8 | . | Fix pgAdmin: set runAsUser: 5050 via PGADMIN_UID; re-enable security headers | V18,V20 |
| T9 | . | Remove lounge initContainer; verify fsGroup handles ownership | V19 |
| T10 | . | Migrate 8 HelmRelease schema URLs from bjw-s to bjw-s-labs (home-assistant, frigate, flood, zwave, cert-manager, wikijs, lounge, seasonpackarr) | V11 |
| T11 | . | Fix corrupted schema URL in monitoring/speedtest-exporter/app/helmrelease.yaml (1n1raw → raw) | V10 |
| T12 | . | Add VolSync coverage: alertmanager PVC, loki 50Gi PVC; evaluate manual ReplicationSource for victoria metrics & logs | V3 |
| T13 | . | Resolve immich REDIS_PASSWORD — un-comment or document explicitly why absent | V16 |
| T14 | . | Add retryInterval: 2m to cilium-gateway Kustomization in cilium/ks.yaml | V12 |
| T15 | . | Audit all privileged/root containers — add inline comments for justified ones (frigate, zwave, multus, gluetun) | V17 |
| T16 | . | Pin busybox image in lounge initContainer to SHA (or remove per T9) | V9 |
| T17 | . | Add memory limit to immich server container (currently commented out) | — |
| T18 | . | Fix recyclarr ks.yaml: document VOLSYNC_CLAIM: recyclarr-config divergence from APP: recyclarr | V14 |
| T19 | . | Migrate Talos config from talhelper (`talconfig.yaml` + `talenv.yaml`) to raw per-node machine configs; remove talhelper dep from mise; update `task talos:*` targets | — |
| T20 | . | Migrate task runner from Taskfile (6 files, ~20 tasks) to Justfile; remove `go-task` from mise | — |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | `FLOOD_OPTION_QBPASS: dummy` hardcoded; envFrom ref commented out → qBittorrent WebUI passwordless | V21 |
| B2 | 2026-04-25 | `monitoring/speedtest-exporter` schema URL `1n1raw.githubusercontent.com` typo → IDE validation broken | V10 |
| B3 | 2026-04-25 | rook-ceph cluster cpu limits on osd/mon/mgr → I/O throttle under load | V8 |
