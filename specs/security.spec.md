# security spec

Extends: SPEC.md §V17–V21

## §G — Goal

Cluster defense-in-depth: least-privilege containers, pinned images, enforced pod security, network segmentation, secret hygiene, hardened workload surfaces.

---

## §C — Constraints

- Talos nodes run CIS-hardened kernel; node-level hardening out of scope here
- Cilium handles NetworkPolicy enforcement
- cert-manager issues TLS; all internal traffic TLS-terminated at gateway
- Pod Security Admission available at k8s 1.25+; enforce per-namespace
- Hardware-access workloads (frigate/Coral, zwave/USB, multus/CNI, gluetun/WireGuard) require privilege exceptions — must be explicit, not default

---

## §I — Interfaces

```
api: PodSecurity admission   → namespace label pod-security.kubernetes.io/enforce
api: NetworkPolicy           → CiliumNetworkPolicy | NetworkPolicy resources
api: seccomp                 → securityContext.seccompProfile.type: RuntimeDefault | Localhost
api: AppArmor                → securityContext.appArmorProfile (k8s 1.30+)
```

---

## §V — Invariants

### Container privileges

```
V1:  privileged: true | runAsUser: 0 → ! inline comment citing specific hardware/capability requirement  [≡ V.core.17]
V2:  ∀ container without hardware requirement → runAsNonRoot: true & runAsUser ≠ 0
V3:  ∀ container → readOnlyRootFilesystem: true | explicit comment why not
V4:  ∀ container → allowPrivilegeEscalation: false (except V1 exceptions)
V5:  ∀ container → drop: [ALL] capabilities; add only specific caps needed
```

### Pod-level security

```
V6:  ∀ pod → seccompProfile.type: RuntimeDefault (minimum)
V7:  ∀ pod → securityContext.fsGroupChangePolicy: OnRootMismatch (not Always — avoids chown on large volumes)
V8:  hostNetwork: true | hostPID: true | hostIPC: true → ! inline comment + restricted to system namespace
V9:  initContainers for chown ⊥ when fsGroup covers it  [≡ V.core.19]
```

### Images

```
V10: ∀ image → pinned tag + SHA digest | semantic version tracked by Renovate  [≡ V.core.9]
V11: latest | master | main tags ⊥  [≡ V.core.9]
V12: ∀ base image → known publisher; no unverified community images for privileged workloads
```

### Secrets

```
V13: ∀ ExternalSecret → refreshInterval: 5m  [≡ V.core.15]
V14: plaintext credentials in helmrelease values ⊥ — use secretKeyRef | envFrom  [≡ V.core.21]
V15: commented-out secret refs → resolve (either use or delete); ⊥ silent gaps
V16: Dragonfly shared across apps → each app uses distinct DB index; auth enabled or isolation documented
```

### Network

```
V17: ∀ namespace → CiliumNetworkPolicy default-deny egress + ingress; allow-list per app
V18: ∀ app exposed externally → gateway: external; internal-only apps → gateway: internal ⊥ external
V19: cross-namespace traffic → explicit NetworkPolicy allow; implicit allow ⊥
```

### Web-facing workloads

```
V20: ∀ web app → security response headers enabled (X-Content-Type-Options, X-XSS-Protection, HSTS)
V21: pgAdmin → runAsUser: 5050 via PGADMIN_UID; security headers ⊥ disabled  [≡ V.core.18,V.core.20]
```

### Pod Security Admission

```
V22: system namespaces (kube-system, rook-ceph, network) → baseline enforce
V23: app namespaces (downloads, media, self-hosted, home-automation) → restricted enforce | privileged exception per-pod annotation
V24: ∀ PSA exception → tracked in this spec §B
```

---

## §T — Tasks

### Immediate (from existing findings)

| id | status | task | cites |
|----|--------|------|-------|
| T1 | x | Fix pgAdmin: pod securityContext runAsUser/Group/NonRoot: 5050 + fsGroup: 5050 (RBD root-owned PVC; fsGroup triggers kubelet recursive chown); add PGADMIN_UID: "5050"; remove X_CONTENT_TYPE_OPTIONS & X_XSS_PROTECTION disables; keep ENHANCED_COOKIE_PROTECTION: "False" (required behind Envoy reverse proxy) | V2,V21 |
| T2 | . | Remove lounge initContainer; confirm fsGroup: 1000 covers ownership | V9 |
| T3 | . | Un-comment or delete immich REDIS_PASSWORD in ExternalSecret; document dragonfly DB index isolation | V15,V16 |
| T4 | . | Fix flood: remove FLOOD_OPTION_QBPASS: dummy; un-comment envFrom secret ref | V14 |
| T5 | . | Add inline justification comments to frigate, zwave, multus, gluetun privileged containers | V1 |
| T6 | . | Pin lounge initContainer busybox to SHA (or remove per T2) | V10,V11 |
| T7 | . | Add memory limit to immich server (currently commented out) | V3 |

### Hardening (new work)

| id | status | task | cites |
|----|--------|------|-------|
| T8  | . | Audit ∀ app containers — add readOnlyRootFilesystem: true + tmpfs mounts where needed | V3 |
| T9  | . | Audit ∀ app containers — add allowPrivilegeEscalation: false & drop: [ALL] | V4,V5 |
| T10 | . | Add seccompProfile: RuntimeDefault to ∀ pods missing it | V6 |
| T11 | . | Set fsGroupChangePolicy: OnRootMismatch on ∀ pods with volume mounts | V7 |
| T12 | . | Design & apply CiliumNetworkPolicy default-deny per namespace; start with downloads & media | V17,V19 |
| T13 | . | Enable Pod Security Admission labels on app namespaces (downloads, media, self-hosted) | V22,V23 |
| T14 | . | Enable Pod Security Admission labels on system namespaces (kube-system, network, rook-ceph) | V22 |
| T15 | . | Audit all externally-exposed HTTPRoutes — confirm only intended apps use gateway: external | V18 |
| T16 | . | Add HSTS + security headers at Envoy Gateway level (global policy, not per-app) | V20 |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | `FLOOD_OPTION_QBPASS: dummy` + commented envFrom → qBittorrent WebUI passwordless | V14 |
| B2 | 2026-04-25 | pgAdmin `runAsUser: 0` + XSS/cookie headers disabled → unnecessary attack surface on internal app | V2,V21 |
| B3 | 2026-04-25 | immich ExternalSecret `REDIS_PASSWORD` commented out → dragonfly auth gap or silent misconfiguration | V15,V16 |
