# volsync spec

Extends: SPEC.md §V3

## §G — Goal

∀ stateful app on ceph-block → automated backup via VolSync → NFS restic REST server. Restore path tested & documented.

---

## §C — Constraints

- VolSync operator manages `ReplicationSource` & `ReplicationDestination`
- Backend (target): NFS-backed restic REST server deployed in-cluster; credentials via ExternalSecret
- Backend (current): MinIO (S3-compatible) — being replaced
- Standard component: `components/volsync/` — `minio.yaml` replaced by `nfs.yaml` during migration
- Operator-managed PVCs (victoria, loki, alertmanager) require manual `ReplicationSource` outside component
- NFS-backed PVCs (immich media) ⊥ volsync — filesystem-level backup handles those
- rook-ceph itself ⊥ volsync — Ceph manages its own replication
- restic mover type retained — only repository backend changes (S3 → REST)
- ∀ existing MinIO snapshots → accessible for restore until MinIO decommissioned; migrate last snapshot per app before cutover

---

## §I — Interfaces

```
component: components/volsync/nfs.yaml  → ReplicationSource + ReplicationDestination (NFS target)
component: components/volsync/minio.yaml → legacy; removed after migration complete
cmd: task volsync:snapshot APP=<name> NS=<ns>   → triggers immediate snapshot
cmd: task volsync:restore  APP=<name> NS=<ns> PREVIOUS=<id> → restores from snapshot
cmd: task volsync:list     APP=<name> NS=<ns>   → lists available snapshots
cmd: task volsync:snapshot-all                  → snapshots ∀ configured apps
env: VOLSYNC_CAPACITY   ! set in ks.yaml postBuild.substitute
env: APP                ! set in ks.yaml postBuild.substitute
env: VOLSYNC_CLAIM      ? overrides PVC name (default: ${APP})
restic-rest: http://volsync-restic-rest.volsync-system.svc:8000  → REST server endpoint
restic-pvc:  NFS storageClass PVC → mounted by REST server pod as repository root
```

---

## §V — Invariants

### Coverage

```
V1: ∀ app with storageClass: ceph-block → volsync component ∈ app/kustomization.yaml  [≡ V.core.3]
V2: operator-managed PVCs (victoria-metrics, victoria-logs, loki, alertmanager) → manual ReplicationSource in app/
V3: cache PVCs (jellyfin-cache, jellyseerr-cache) ? volsync — loss non-critical but document decision
```

### Component & naming

```
V4: VOLSYNC_CLAIM override ≠ APP value → inline comment required  [≡ V.core.14]
V5: ∀ ReplicationSource & ReplicationDestination in same app → same moverSecurityContext
V6: moverSecurityContext → runAsUser: 568, runAsGroup: 568, fsGroup: 568 (or match app uid)
```

### Security

```
V7:  moverSecurityContext ! defined on both ReplicationSource & ReplicationDestination
V8:  ReplicationDestination moverSecurityContext ⊥ commented-out
V9:  restic REST server → auth enabled (htpasswd); credentials in ExternalSecret ⊥ plaintext
V10: restic REST server → `--no-auth` ⊥
```

### NFS backend

```
V11: restic REST server PVC → NFS storageClass; ⊥ ceph-block (backup target ≠ backup source)
V12: RESTIC_REPOSITORY → rest:http://volsync-restic-rest.volsync-system.svc:8000/${APP}
V13: REST server data path per-app → /${APP}/ subdirectory; ⊥ shared flat repo
V14: REST server pod → readOnlyRootFilesystem: true; repo PVC mounted at /data
```

### Migration safety

```
V15: ∀ app → final MinIO snapshot taken before switching component to nfs.yaml
V16: ∀ app → NFS restore test (ReplicationDestination triggered) before MinIO component removed
V17: MinIO component (minio.yaml) ⊥ removed until ∀ apps migrated & V16 satisfied
V18: MinIO ExternalSecret & secret → deleted per-app only after NFS backup confirmed
```

### Reliability

```
V19: ∀ ReplicationSource → schedule defined (cron expression)
V20: ∀ ReplicationSource → retain policy defined (daily/weekly minimums)
```

---

## §T — Tasks

### Phase 0 — Pre-migration fixes (MinIO still active)

| id | status | task | cites |
|----|--------|------|-------|
| T1 | . | Un-comment moverSecurityContext on ReplicationDestination in `components/volsync/minio.yaml` | V7,V8 |
| T2 | . | Audit ∀ ReplicationSource/Destination pairs — verify moverSecurityContext matches app uid | V5,V6 |

### Phase 1 — NFS backend setup

| id | status | task | cites |
|----|--------|------|-------|
| T3 | . | Provision NFS PVC for restic REST server repository root (⊥ ceph-block) | V11 |
| T4 | . | Deploy restic REST server (app: `volsync-restic-rest`, ns: `volsync-system`) with htpasswd auth & NFS PVC at /data | V9,V10,V14 |
| T5 | . | Add REST server credentials to 1Password; create ExternalSecret `volsync-nfs-template` | V9 |
| T6 | . | Create `components/volsync/nfs.yaml` — ExternalSecret using `volsync-nfs-template`, ReplicationSource & ReplicationDestination with `RESTIC_REPOSITORY: rest:http://.../${APP}` | V12,V13 |
| T7 | . | Update `components/volsync/kustomization.yaml` — add `nfs.yaml`; keep `minio.yaml` until migration done | V17 |

### Phase 2 — App migration (repeat per app)

| id | status | task | cites |
|----|--------|------|-------|
| T8  | . | Take final MinIO snapshot: `task volsync:snapshot APP=<name> NS=<ns>` | V15 |
| T9  | . | Switch app `kustomization.yaml` component from `minio.yaml` → `nfs.yaml` | V17 |
| T10 | . | Trigger NFS ReplicationSource — verify snapshot written to REST server | V16 |
| T11 | . | Trigger NFS ReplicationDestination (restore-once) — verify PVC recovers cleanly | V16 |
| T12 | . | Delete app MinIO ExternalSecret & secret after V16 confirmed | V18 |

Apps to migrate (in order — lowest risk first):
1. recyclarr, autobrr, cross-seed, seasonpackarr
2. prowlarr, radarr, sonarr, flood, qbittorrent
3. frigate, zwave, home-assistant
4. jellyfin, jellyseerr, lounge, wikijs
5. paperless, unifi, harbor, pgadmin, donetick

### Phase 3 — Operator-managed PVCs (NFS from the start)

| id | status | task | cites |
|----|--------|------|-------|
| T13 | . | Add manual ReplicationSource for alertmanager PVC → NFS backend | V1,V2 |
| T14 | . | Add manual ReplicationSource for loki 50Gi PVC → NFS backend | V1,V2 |
| T15 | . | Add manual ReplicationSource for victoria-metrics VmSingle PVC → NFS backend | V2 |
| T16 | . | Add manual ReplicationSource for victoria-logs VLSingle PVC → NFS backend | V2 |

### Phase 4 — Cleanup

| id | status | task | cites |
|----|--------|------|-------|
| T17 | . | Remove `components/volsync/minio.yaml` after ∀ apps migrated | V17 |
| T18 | . | Remove `minio.yaml` from `components/volsync/kustomization.yaml` | V17 |
| T19 | . | Document cache PVC decision for jellyfin-cache & jellyseerr-cache | V3 |
| T20 | . | Decommission MinIO instance if volsync was its only consumer | — |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | `moverSecurityContext` commented out on `ReplicationDestination` in `components/volsync/minio.yaml` → mover runs as root → restored files may have wrong ownership | V7,V8 |
