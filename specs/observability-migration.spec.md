# observability-migration spec

## §G — Goal

Replace Prometheus + Promtail + Loki with OTel collectors + VictoriaMetrics + VictoriaLogs. Complete cutover — no gradual migration, no dual-run, no compat layer. Dashboards rewritten from scratch against new backends. Brief observability gap during cutover acceptable.

---

## §C — Constraints

- VictoriaMetrics stack (operator, VMSingle, VMAlert, VLSingle) deployed & receiving data
- OTel agent (DaemonSet) + gateway (Deployment) deployed & routing to Victoria
- OTel TargetAllocator (`prometheusCR.enabled: true`, empty selectors) scrapes ∀ ServiceMonitor/PodMonitor cluster-wide
- VMAlert (`selectAllByDefault: true`) reads ∀ PrometheusRule objects
- `prometheus-operator/crds` ! remain: VMAlert + VMAgent read `PrometheusRule`/`ServiceMonitor`/`PodMonitor` CRDs
- alertmanager standalone + silence-operator → unchanged
- VLSingle endpoint: `http://vlsingle-logs.monitoring:9428`; VMSingle Prometheus-compat: `http://vmsingle-metrics.monitoring.svc:8429`
- Traces pipeline commented out in gateway (future: VictoriaTraces)
- ⊥ compat between old & new: Loki/Prometheus removed wholesale, dashboards rewritten

---

## §I — Interfaces

```
metrics write:  OTel gateway → otlphttp → vmsingle-metrics.monitoring.svc:8428/opentelemetry
metrics query:  VMSingle Prometheus-compat API → vmsingle-metrics.monitoring.svc:8429
logs write:     OTel gateway → otlphttp → vlsingle-logs.monitoring:9428/insert/opentelemetry
logs query:     VLSingle → vlsingle-logs.monitoring:9428 (VictoriaLogs query API, LogsQL)
alerting:       VMAlert → alertmanager.monitoring.svc:9093
scrape:         OTel TargetAllocator (per-node) → ServiceMonitor/PodMonitor → agent → gateway → VMSingle
```

---

## §V — Invariants

### Cutover

```
V1:  cutover atomic per component — no dual-run gates; brief gap acceptable
V2:  prometheus-operator/crds ⊥ removed — VMAlert depends on PrometheusRule CRDs
V3:  kube-prometheus-stack removed entirely — no dashboard-only retention
V4:  ⊥ Loki, ⊥ Promtail, ⊥ Prometheus instance post-cutover
```

### OTel pipeline

```
V5:  OTel agent → gateway via OTLP (insecure gRPC port 4317); ⊥ direct Victoria writes from agent
V6:  TargetAllocator allocationStrategy: per-node → each agent scrapes only local-node targets
V7:  ∀ ServiceMonitor/PodMonitor → picked up by TargetAllocator (empty selectors)
V8:  OTel gateway exporters: victoriametrics (metrics) & victorialogs (logs); traces ? future
V9:  memory_limiter processor ∈ ∀ pipeline
```

### Victoria

```
V10: VMSingle retention: 2w, storage: 30Gi ceph-block
V11: VLSingle retention: 2w, storage: 10Gi ceph-block
V12: VMAlert evaluationInterval: 1m
V13: VMAlert notifiers → alertmanager.monitoring.svc:9093
V14: ∀ PrometheusRule objects → read by VMAlert; ⊥ rule migration needed
```

### Grafana

```
V15: Grafana Prometheus datasource URL → http://vmsingle-metrics.monitoring.svc:8429
V16: Grafana Loki datasource removed; VictoriaLogs datasource added → http://vlsingle-logs.monitoring:9428
V17: ∀ dashboards rewritten from scratch — ⊥ LogQL→LogsQL translation, ⊥ legacy KPS dashboards retained
V18: dashboard sources: official VictoriaMetrics community dashboards + hand-written ConfigMaps with `grafana_dashboard: "1"` label & `grafana_folder` annotation
```

### Cleanup retain

```
V19: node-exporter & kube-state-metrics remain — OTel hostmetrics/k8s_cluster ⊥ full replacement
V20: blackbox-exporter remains — OTel ⊥ replaces ICMP/TCP_connect probing (B4)
```

### OTel label fidelity

```
V21: ∀ prometheus-scraped metrics in VMSingle → `job` label present & = scrape job_name; ∴ PrometheusRule job= filters match (B5)
V22: TargetAllocator ⊥ honor ServiceMonitor `jobLabel` → gateway transform processor renames job values to expected names (B6); moot post-T16
V23: apiserver scraped via static job / k8s_cluster receiver — per-node TA cannot allocate Talos static-pod targets (B3)
V24: transform/add_job_label ⊥ overwrite pre-set `job` on OTLP-pushed metrics; stmts 1&2 (nil-guard) sufficient for prometheus-sourced metrics; stmt 3 removed (B7)
```

---

## §T — Tasks

### Phase 1 — Pre-cutover (DONE)

| id | status | task | cites |
|----|--------|------|-------|
| T1 | x | OTel/Victoria stack deployed & ingesting | V5,V8 |
| T2 | x | TargetAllocator + VMAlert wired to existing SM/PM/PrometheusRule | V7,V14 |
| T3 | x | Fix B3: apiserver static scrape job in OTel agent | V23 |
| T4 | x | Fix B5: gateway `transform/add_job_label` stmts 1&2 — set job from service.name when nil | V21 |
| T5 | x | Audit blackbox Probe CRs — keep blackbox-exporter (OTel ⊥ cover) | V20 |

### Phase 2 — Dashboard rewrite

| id | status | task | cites |
|----|--------|------|-------|
| T6  | x | Add VMSingle Grafana datasource (Prometheus-compat URL) | V15 |
| T7  | x | Add VLSingle Grafana datasource | V16 |
| T8  | x | Inventory current dashboards → drop list (KPS-injected, Loki-backed, custom) | V17 |
| T9  | x | Import official VictoriaMetrics community dashboards (Kubernetes, node-exporter, kube-state-metrics) as ConfigMaps | V18 |
| T10 | . | Write new VictoriaLogs LogsQL dashboards from scratch (flux-logs, app logs, ingress) | V17,V18 |
| T11 | . | Write any custom app dashboards needed against VMSingle/VLSingle | V18 |
| T12 | x | Remove Grafana Loki datasource | V16 |
| T22 | x | Fix B7: remove stmt 3 from `transform/add_job_label` in otel-gateway; stmts 1&2 sufficient | V24,B7 |

### Phase 3 — Rip out old stack

| id | status | task | cites |
|----|--------|------|-------|
| T13 | x | Remove promtail HelmRelease + ks.yaml + monitoring/kustomization.yaml entry | V4 |
| T14 | x | Remove loki HelmRelease + ks.yaml + monitoring/kustomization.yaml entry | V4 |
| T15 | . | Delete loki ceph-block PVC (50Gi recovered) | V4 |
| T16 | . | Remove kube-prometheus-stack HelmRelease + ks.yaml entirely (Prometheus + Grafana dashboard sidecar injection both gone) | V3,V4 |
| T17 | . | Verify `prometheus-operator-crds` HelmRelease still present (VMAlert deps) | V2 |
| T18 | . | Remove monitoring/kustomization.yaml entries for KPS | V3 |
| T19 | . | Post-cutover: confirm VMAlert firing rules, alertmanager receiving, dashboards rendering | V12,V13,V14 |

### Phase 4 — Traces (future)

| id | status | task | cites |
|----|--------|------|-------|
| T20 | ? | Deploy VictoriaTraces (VTSingle) when available | V8 |
| T21 | ? | Un-comment traces pipeline in otel-gateway.yaml | V8 |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | Promtail + OTel filelog both shipping `/var/log/pods` → duplicate entries during overlap | resolved by atomic cutover (V1); ⊥ recurs post-T13 |
| B2 | 2026-05-01 | `kube-prometheus-stack-operator` SM skipped by TA: SA `open-telemetry-agent-targetallocator` lacks `get secrets` in `monitoring` ns. TA ⊥ fetch TLS CA. | moot post-T16 (KPS removed) |
| B3 | 2026-05-01 | `apiserver` SM 0 targets allocated under per-node strategy (Talos static pod, no matching collector). | V23 |
| B4 | 2026-05-01 | Blackbox Probe CRs absent from TA job list — `probeSelector` missing. | added `probeSelector: {}` to TA prometheusCR; blackbox-exporter retained per V20 |
| B5 | 2026-05-01 | OTel prometheus receiver maps `job` → `service.name`; VMSingle missing `job` label → PrometheusRule `job=` filters empty. | V21 — `transform/add_job_label` processor in gateway |
| B6 | 2026-05-01 | TA ⊥ honor ServiceMonitor `jobLabel` → job stays as SM name (e.g. `kube-prometheus-stack-kubelet` not `kubelet`). | V22 — `metricstransform`/`transform` processor renames job values; moot per-job once KPS SMs gone (T16) |
| B7 | 2026-05-03 | `transform/add_job_label` stmt 3 unconditionally overwrites `job`=`service.name` ∀ metrics where they differ — clobbers OTLP app-set `job` labels | V24 — remove stmt 3; stmts 1&2 nil-guard sufficient (T22) |
| B8 | 2026-05-03 | `grafana` helmrelease datasources block adds `Prometheus` (url: `prometheus-operated…:9090`, `isDefault: true`) then deletes it via `deleteDatasources` → net: no default datasource; `VictoriaMetrics` (:8429) present but ⊥ `isDefault` | V15 — remove stale Prometheus entry; set `VictoriaMetrics` `isDefault: true` (fix in T16 cleanup) |
