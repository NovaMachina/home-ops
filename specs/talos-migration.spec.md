# talos-migration spec

Extends: SPEC.md T19

## §G — Goal

Replace talhelper abstraction with raw `talosctl`-managed configs. Cluster stays live throughout; ∀ 9 nodes re-applied with functionally identical config.

---

## §C — Constraints

- 9 nodes: 3 controllers (10.0.40.100–102), 3 workers (10.0.40.103–105), 3 storage (10.0.40.106–108)
- 3 controller patches + 5 global patches → must all survive migration verbatim
- worker-02 (10.0.40.104) & worker-03 (10.0.40.105) have distinct factory installer URLs (different extensions vs rest of cluster)
- `talsecret.sops.yaml` is talhelper-specific format → must migrate to `talosctl gen secrets` bundle format before talhelper removed
- Renovate tracks `talosVersion` + `kubernetesVersion` via `talenv.yaml` comments — tracking must survive talhelper removal
- `talos/clusterconfig/` holds current generated configs — can be used as reference for diff validation
- `talhelper` dep in mise → removed after migration; `talosctl` already present
- Taskfile: 5 tasks reference talhelper (`generate-config`, `apply-node`, `upgrade-node`, `upgrade-k8s`, `reset`) → all replaced with `talosctl` equivalents
- Cluster must stay healthy (Ceph HEALTH_OK) before + after each node apply — existing `down`/`up` task guards remain

---

## §I — Interfaces

```
cmd: talosctl gen secrets --output-file talos/secrets.sops.yaml  → secrets bundle
cmd: talosctl gen config  <cluster-name> https://10.0.40.10:6443 \
       --with-secrets talos/secrets.sops.yaml \
       --config-patch @<patch> \
       --output-dir talos/clusterconfig/              → per-node machine configs
cmd: talosctl apply-config --nodes <IP> --file talos/clusterconfig/<node>.yaml --mode <mode>
cmd: talosctl upgrade      --nodes <IP> --image <factory-url>:<version>
cmd: talosctl upgrade-k8s  --to <version>
cmd: talosctl reset        --nodes <IP> --reboot ...
file: talos/nodes/<hostname>.yaml     → per-node patch (network, installDisk, hostname)
file: talos/patches/global/*.yaml     → unchanged; applied to ∀ nodes
file: talos/patches/controller/*.yaml → unchanged; applied to controllers only
file: talos/secrets.sops.yaml         → talosctl secrets bundle, SOPS-encrypted (replaces talsecret.sops.yaml)
file: talos/talenv.yaml               → kept for Renovate version tracking only; talhelper schema comment removed
```

---

## §V — Invariants

### Config correctness

```
V1: generated configs ∀ 9 nodes → diff against current clusterconfig/ before any apply; ⊥ unexpected changes
V2: ∀ node config → same patches as talhelper output (global/* + controller/* for controllers)
V3: per-node values (hostname, IP, MAC, installDisk, talosImageURL) ∈ talos/nodes/<hostname>.yaml patch
V4: VIP 10.0.40.10 ∈ ∀ controller node configs
V5: worker-02 & worker-03 installer URLs differ from other nodes — per-node patch, ⊥ shared default
```

### Secrets

```
V6: secrets bundle (talos/secrets.sops.yaml) → extracted from live cluster via `talosctl gen secrets --from-controlplane-config` | converted from talsecret.sops.yaml — ⊥ regenerated fresh (would rotate certs)
V7: talos/secrets.sops.yaml → SOPS-encrypted (.sops.yaml suffix matches .sops.yaml rules)
V8: talsecret.sops.yaml ⊥ deleted until V6 confirmed & new secrets applied to ∀ nodes
```

### Renovate

```
V9:  talos/talenv.yaml retained post-migration; contains talosVersion + kubernetesVersion with Renovate comments
V10: talhelper schema comment (`$schema: .../talconfig.json`) removed from talenv.yaml after migration
```

### Taskfile

```
V11: task talos:generate-config → `talosctl gen config` applying patches; ⊥ talhelper
V12: task talos:apply-node      → `talosctl apply-config`; ⊥ talhelper
V13: task talos:upgrade-node    → `talosctl upgrade`; reads talosImageURL from talos/nodes/<hostname>.yaml & version from talenv.yaml
V14: task talos:upgrade-k8s     → `talosctl upgrade-k8s`; reads kubernetesVersion from talenv.yaml
V15: task talos:reset           → `talosctl reset`; ⊥ talhelper
V16: talhelper removed from mise tools after ∀ tasks migrated
```

### Migration safety

```
V17: ∀ node → apply one at a time; wait for Ceph HEALTH_OK before next node
V18: controllers applied last (or rolling, one at a time); ⊥ simultaneous multi-controller apply
V19: ∀ node → `talosctl get machineconfig --nodes <IP>` confirms new config active after apply
V20: talconfig.yaml & talsecret.sops.yaml → archived (git history); deleted from working tree only after ∀ nodes confirmed
```

---

## §T — Tasks

### Phase 1 — Prepare secrets

| id | status | task | cites |
|----|--------|------|-------|
| T1 | . | Extract secrets bundle from live cluster: `talosctl gen secrets --from-controlplane-config talos/clusterconfig/kubernetes-talos-controller-01.yaml --output-file talos/secrets.sops.yaml` | V6 |
| T2 | . | Encrypt `talos/secrets.sops.yaml` with SOPS: `sops --encrypt --in-place talos/secrets.sops.yaml` | V7 |
| T3 | . | Verify decrypted bundle fields match `talsecret.sops.yaml` (cluster.id, cluster.secret, certs.etcd) | V6,V8 |

### Phase 2 — Build per-node patch files

| id | status | task | cites |
|----|--------|------|-------|
| T4 | . | Create `talos/nodes/talos-controller-01.yaml` through `talos-storage-03.yaml` — each with hostname, IP, MAC, installDisk, talosImageURL | V3,V5 |
| T5 | . | Confirm worker-02 & worker-03 node patches reference their distinct factory installer URLs | V5 |

### Phase 3 — Update generate-config task & validate

| id | status | task | cites |
|----|--------|------|-------|
| T6 | . | Rewrite `task talos:generate-config` to use `talosctl gen config` with `--with-secrets`, global patches, controller patches, per-node patches | V11 |
| T7 | . | Run new generate-config; diff output in `talos/clusterconfig/` against current files — resolve ∀ unexpected diffs before proceeding | V1,V2 |

### Phase 4 — Update remaining Taskfile tasks

| id | status | task | cites |
|----|--------|------|-------|
| T8  | . | Rewrite `task talos:apply-node` → `talosctl apply-config` | V12 |
| T9  | . | Rewrite `task talos:upgrade-node` → `talosctl upgrade`; source image URL from `talos/nodes/<hostname>.yaml`, version from `talenv.yaml` | V13 |
| T10 | . | Rewrite `task talos:upgrade-k8s` → `talosctl upgrade-k8s --to`; source version from `talenv.yaml` | V14 |
| T11 | . | Rewrite `task talos:reset` → `talosctl reset` | V15 |
| T12 | . | Remove `which talhelper` preconditions from ∀ tasks | V16 |

### Phase 5 — Rolling apply to cluster

| id | status | task | cites |
|----|--------|------|-------|
| T13 | . | Apply workers first (10.0.40.103–105), one at a time; verify each via V19 | V17,V19 |
| T14 | . | Apply storage nodes (10.0.40.106–108), one at a time; verify each | V17,V19 |
| T15 | . | Apply controllers (10.0.40.100–102) one at a time; verify each; confirm etcd healthy after each | V17,V18,V19 |

### Phase 6 — Cleanup

| id | status | task | cites |
|----|--------|------|-------|
| T16 | . | Remove `talhelper` from `mise.toml` tools | V16 |
| T17 | . | Remove `talconfig.yaml` from repo | V20 |
| T18 | . | Remove `talsecret.sops.yaml` from repo | V8,V20 |
| T19 | . | Remove talhelper schema comment from `talenv.yaml`; keep version fields for Renovate | V9,V10 |
| T20 | . | Update CLAUDE.md: replace `talconfig.yaml` references with new config structure | — |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
