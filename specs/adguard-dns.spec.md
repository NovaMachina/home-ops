# adguard-dns spec

## §G — Goal

Evaluate `external-dns-provider-adguard` as internal DNS solution; close gap where `*.${SECRET_DOMAIN}` resolves on home network without requiring k8s_gateway in-cluster DNS.

---

## §C — Constraints

- CoreDNS currently forwards `.` → `/etc/resolv.conf`; no k8s_gateway plugin deployed despite CLAUDE.md mention — internal hostname resolution for `*.${SECRET_DOMAIN}` is an open gap
- external-dns-cloudflare instance already deployed; watches `gateway-name=external` only → writes to Cloudflare
- Internal gateway LB IPs: `internal` → 10.0.40.3, `internal-root` → 10.0.40.20
- AdGuard Home assumed deployed on home network as primary resolver for local devices (? — verify before implementing)
- `external-dns-provider-adguard` is a community webhook provider (not upstream external-dns) — runs as a sidecar to external-dns via webhook API
- AdGuard DNS rewrites are flat key→value (hostname → IP); ⊥ zone authority, ⊥ wildcards via API (only exact matches | regex in newer versions)
- SOPS+age secrets; AdGuard credentials → ExternalSecret from 1Password

---

## §I — Interfaces

```
api: AdGuard Home API → http(s)://<adguard-ip>/control (basic auth)
webhook: external-dns-provider-adguard → localhost:8888 (sidecar to external-dns pod)
dns-rewrite: AdGuard Home → hostname: app.${SECRET_DOMAIN} → 10.0.40.3
src: gateway-httproute, gateway-name=internal → ∀ internal app hostnames
```

---

## §V — Investigation questions

```
Q1: AdGuard Home deployed & accessible from cluster? IP? API enabled?
Q2: AdGuard provider supports wildcard rewrites (*.${SECRET_DOMAIN} → 10.0.40.3) or only per-hostname?
Q3: ∀ internal HTTPRoutes use gateway-name=internal exclusively (⊥ external gateway)?
Q4: Provider maturity — release cadence, open issues, Renovate trackable?
Q5: Split-brain risk: external-dns creates rewrite for hostname that also exists in Cloudflare?
```

---

## §V — Invariants (post-investigation, conditional on Q1–Q4)

### Architecture

```
V1: external-dns-cloudflare (existing) → watches gateway-name=external; writes to Cloudflare; unchanged
V2: external-dns-adguard (new) → watches gateway-name=internal; writes AdGuard rewrites only
V3: ∀ internal hostname → AdGuard rewrite → 10.0.40.3 | 10.0.40.20 (root gateway)
V4: ∀ external hostname ⊥ AdGuard rewrite — Cloudflare handles; split-brain prevented by gateway filter
V5: AdGuard provider runs as sidecar container in external-dns-adguard pod (webhook mode)
```

### k8s_gateway comparison

```
V6: k8s_gateway ⊥ deployed if AdGuard provider covers internal resolution — ⊥ both
V7: AdGuard rewrites survive cluster restart (persistent in AdGuard config) — k8s_gateway ⊥ (in-cluster DNS dies with pod)
V8: AdGuard provider requires AdGuard reachable from cluster — single point of failure risk; ? HA AdGuard setup
```

### Config

```
V9:  external-dns-adguard → separate HelmRelease + ks.yaml under network/external-dns/adguard/
V10: AdGuard credentials ∈ ExternalSecret referencing ClusterSecretStore/onepassword
V11: provider: webhook; webhook.url: http://localhost:8888
V12: sources: [gateway-httproute]; gateway-name: internal
V13: policy: sync — AdGuard rewrites reconciled on HTTPRoute add/remove
```

---

## §T — Tasks

### Phase 1 — Investigation

| id | status | task | cites |
|----|--------|------|-------|
| T1 | . | Verify AdGuard Home deployed on home network; confirm API accessible at known IP from cluster pods | Q1 |
| T2 | . | Test AdGuard API: `curl http://<ip>/control/rewrite/list` — confirm auth works, list current rewrites | Q1 |
| T3 | . | Audit external-dns-provider-adguard repo: version, last release, open issues, wildcard rewrite support | Q2,Q4 |
| T4 | . | Enumerate ∀ internal HTTPRoutes — confirm all use `parentRefs[].name: internal` or `internal-root` | Q3 |
| T5 | . | Check if AdGuard supports regex/wildcard rewrites (`*.${SECRET_DOMAIN}`) — if yes, single rewrite replaces per-hostname entries | Q2 |

### Phase 2 — Implementation (if investigation passes)

| id | status | task | cites |
|----|--------|------|-------|
| T6  | . | Add AdGuard credentials to 1Password vault homelab | V10 |
| T7  | . | Create `network/external-dns/adguard/` HelmRelease with external-dns + adguard webhook sidecar | V5,V9,V11,V12 |
| T8  | . | Create ExternalSecret for AdGuard credentials | V10 |
| T9  | . | Add `network/external-dns/adguard/ks.yaml`; add to `network/external-dns/kustomization.yaml` | V9 |
| T10 | . | Deploy; verify AdGuard rewrite list populated for ∀ internal hostnames | V3,V13 |
| T11 | . | Test resolution from home network device: `nslookup app.${SECRET_DOMAIN}` → 10.0.40.3 | V3 |
| T12 | . | Confirm ⊥ Cloudflare pollution: external hostnames ⊥ in AdGuard rewrite list | V4 |
| T13 | . | Update CLAUDE.md: document DNS architecture (Cloudflare for external, AdGuard for internal) | — |

### Phase 3 — k8s_gateway decision

| id | status | task | cites |
|----|--------|------|-------|
| T14 | . | If AdGuard provider covers ∀ internal resolution needs → formally skip k8s_gateway deployment | V6 |
| T15 | . | If AdGuard HA not available → document single-point-of-failure risk; evaluate fallback (CoreDNS static entries) | V8 |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | CLAUDE.md documents k8s_gateway as deployed but no k8s_gateway HelmRelease exists — internal `*.${SECRET_DOMAIN}` resolution from home network is unresolved gap | V3 |
