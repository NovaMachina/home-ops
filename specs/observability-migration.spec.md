# observability-migration spec

## §G — Goal

Replace Prometheus + Promtail + Loki with OTel collectors + VictoriaMetrics + VictoriaLogs. Zero observability gap during cutover.

---

## §C — Constraints

- VictoriaMetrics stack (operator, VMSingle, VMAlert, VLSingle) already deployed & receiving data
- OTel agent (DaemonSet) + gateway (Deployment) already deployed & routing to Victoria
- OTel TargetAllocator (`prometheusCR.enabled: true`, empty selectors) scrapes ∀ ServiceMonitor/PodMonitor cluster-wide — replaces Prometheus pull
- VMAlert (`selectAllByDefault: true`) reads ∀ PrometheusRule objects — replaces Prometheus alerting
- `prometheus-operator/crds` must remain: VMAlert + VMAgent read `PrometheusRule`/`ServiceMonitor`/`PodMonitor` CRDs; removal breaks alerting
- alertmanager standalone (not in kube-prometheus-stack) + silence-operator → both stay unchanged
- kube-prometheus-stack `grafana.forceDeployDashboards: true` injects Kubernetes dashboards via sidecar → must preserve or migrate before removal
- VLSingle endpoint: `http://vlsingle-logs.monitoring:9428`; Prometheus-compat query at `http://vmsingle-metrics.monitoring.svc:8429`
- OTel `filelog` receiver covers same `/var/log/pods` source as Promtail → duplicate collection until Promtail removed
- Traces pipeline commented out in gateway (future: VictoriaTraces)

---

## §I — Interfaces

```
metrics write:  OTel gateway → otlphttp → vmsingle-metrics.monitoring.svc:8428/opentelemetry
metrics query:  VMSingle Prometheus-compat API → vmsingle-metrics.monitoring.svc:8429
logs write:     OTel gateway → otlphttp → vlsingle-logs.monitoring:9428/insert/opentelemetry
logs query:     VLSingle → vlsingle-logs.monitoring:9428 (VictoriaLogs query API)
alerting:       VMAlert → alertmanager.monitoring.svc:9093
scrape:         OTel TargetAllocator (per-node) → ServiceMonitor/PodMonitor → agent → gateway → VMSingle
```

---

## §V — Invariants

### Cutover safety

```
V1:  ∀ removal step → verify replacement ingesting same data first (query both, compare)
V2:  Promtail removed only after VLSingle confirmed receiving logs from OTel filelog
V3:  Loki removed only after Grafana datasource switched to VLSingle & dashboards validated
V4:  kube-prometheus-stack (Prometheus) removed only after:
       a) VMSingle confirmed receiving ∀ same metrics via OTel TargetAllocator
       b) ∀ Grafana dashboards migrated or confirmed working against VMSingle
       c) Grafana Kubernetes folder dashboards re-injected via alternative method
V5:  prometheus-operator/crds ⊥ removed — VMAlert depends on PrometheusRule CRDs
```

### OTel pipeline

```
V6:  OTel agent → gateway via OTLP (insecure gRPC on port 4317); no direct Victoria writes from agent
V7:  TargetAllocator allocationStrategy: per-node → each agent scrapes only local-node targets
V8:  ∀ ServiceMonitor/PodMonitor → picked up by TargetAllocator (empty selectors) ∴ no per-monitor changes needed
V9:  OTel gateway exporters: victoriametrics (metrics pipeline) & victorialogs (logs pipeline) — traces exporter ? (commented out, future)
V10: memory_limiter processor ∈ ∀ pipeline — prevents OOM under log bursts
```

### Victoria

```
V11: VMSingle retention: 2w, storage: 30Gi ceph-block — review if Prometheus had 14d/55Gi
V12: VLSingle retention: 2w, storage: 10Gi ceph-block — monitor usage; Loki had 50Gi (assess actual utilization first)
V13: VMAlert evaluationInterval: 1m — matches Prometheus scrapeInterval: 1m in kube-prometheus-stack
V14: VMAlert notifiers → alertmanager.monitoring.svc:9093 — same endpoint, no alertmanager changes needed
V15: ∀ PrometheusRule objects → read by VMAlert; no migration of alert rules needed
```

### Grafana

```
V16: Grafana Prometheus datasource URL → http://vmsingle-metrics.monitoring.svc:8429 (Prometheus-compat)
V17: Grafana Loki datasource URL → http://vlsingle-logs.monitoring:9428 (VictoriaLogs query API)
V18: VictoriaLogs query API ≠ Loki API — LogQL dashboards require migration to MetricsQL/VictoriaLogs syntax | replace with official Victoria dashboards
V19: kube-prometheus-stack dashboard injection (grafana_folder: Kubernetes) → replace with victoria-metrics community dashboards or standalone ConfigMaps before KPS removal
```

### Cleanup

```
V20: after full cutover, remove: promtail, loki, kube-prometheus-stack (Prometheus instance only)
V21: kube-prometheus-stack HelmRelease ? kept as dashboard-only (grafana.forceDeployDashboards: true, prometheus disabled) | or migrate dashboards & remove entirely
V22: node-exporter & kube-state-metrics remain — OTel hostmetrics/k8s_cluster partial overlap but not full replacement
V23: blackbox-exporter probes.yaml (Probe CRs) → verify OTel covers | keep blackbox-exporter until confirmed
```

### OTel label fidelity

```
V24: ∀ prometheus-scraped metrics in VMSingle → `job` label present & = scrape job_name; ∴ PrometheusRule job= filters match
```

---

## §T — Tasks

### Phase 1 — Verify (no removals yet)

| id | status | task | cites |
|----|--------|------|-------|
| T1 | x | Query VMSingle: confirm ∀ key metric series present (node, kubelet, kube-state-metrics, app ServiceMonitors) | V1,V4a |
| T2 | x | Query VLSingle: confirm logs arriving from ∀ namespaces via OTel filelog | V1,V2 |
| T3 | x | Compare Prometheus scrape target list vs OTel TargetAllocator target list — identify gaps | V1,V8 |
| T4 | x | Check VMAlert firing/resolved states match Prometheus alertmanager history | V1,V13 |
| T5 | x | Audit Loki storage actual usage (vs 50Gi) to right-size VLSingle 10Gi | V12 |
| T6  | x | Audit blackbox-exporter Probe CRs — determine if OTel covers or must keep | V23 |
| T26 | x | Fix B3: apiserver 0-target gap — add static scrape job (or `k8s_cluster` receiver) to OTel agent for kube-apiserver endpoints; per-node TA cannot allocate static-pod targets on control-plane nodes | V1,V4a,B3 |
| T27 | x | Fix B6: TargetAllocator ignores ServiceMonitor jobLabel — add transform processor in gateway to rename job values (e.g. `kube-prometheus-stack-kubelet` → `kubelet`) so PrometheusRule expressions match | V24,B6 |

### Phase 2 — Grafana cutover

| id | status | task | cites |
|----|--------|------|-------|
| T7  | x | Add VMSingle as Grafana datasource (Prometheus-compat URL) | V16 |
| T8  | x | Add VLSingle as Grafana datasource | V17 |
| T9  | x | Audit ∀ Grafana dashboards using Loki datasource — identify LogQL queries needing rewrite | V18 |
| T10 | . | Replace/rewrite Loki-backed dashboards against VictoriaLogs API | V18 |
| T11 | . | Import victoria-metrics Kubernetes dashboards (replace KPS-injected ones) | V19 |
| T12 | . | Validate ∀ Grafana dashboards against new datasources | V16,V17 |

### Phase 3 — Remove Promtail + Loki

| id | status | task | cites |
|----|--------|------|-------|
| T13 | . | Remove promtail HelmRelease + ks.yaml | V2 |
| T14 | . | Remove promtail from monitoring/kustomization.yaml | V2 |
| T15 | . | Remove loki HelmRelease + ks.yaml after Grafana validated on VLSingle | V3 |
| T16 | . | Remove loki from monitoring/kustomization.yaml | V3 |
| T17 | . | Delete loki ceph-block PVC (50Gi recovered) | V3 |

### Phase 4 — Remove Prometheus

| id | status | task | cites |
|----|--------|------|-------|
| T18 | . | Disable Prometheus in kube-prometheus-stack values (set `prometheus.enabled: false`) | V4 |
| T19 | . | Verify no alerting gap after Prometheus removed (VMAlert covers all rules) | V4,V13,V15 |
| T20 | . | Decide: keep kube-prometheus-stack for dashboard injection only OR remove entirely & use ConfigMap dashboards | V21 |
| T21 | . | If removing KPS entirely: migrate Kubernetes dashboards to standalone ConfigMaps with grafana_folder annotation | V19,V21 |
| T22 | . | Remove kube-prometheus-stack HelmRelease + ks.yaml (after T20 decision) | V4 |
| T23 | . | Remove prometheus-operator from kube-prometheus-stack values; keep CRDs HelmRelease | V5 |

### Phase 5 — Traces (future)

| id | status | task | cites |
|----|--------|------|-------|
| T24 | ? | Deploy VictoriaTraces (VTSingle) when available | V9 |
| T25 | ? | Un-comment traces pipeline in otel-gateway.yaml | V9 |

---

## §B — Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-04-25 | Promtail + OTel filelog both shipping same `/var/log/pods` logs → duplicate entries in Loki & VLSingle during overlap | V2 |
| B2 | 2026-05-01 | `kube-prometheus-stack-operator` SM skipped by TA: SA `open-telemetry-agent-targetallocator` lacks `get secrets` in `monitoring` ns — cannot fetch TLS CA `kube-prometheus-stack-admission`. TA logs: `skipping servicemonitor` every 5m. Prometheus scrapes 1 target; OTel scrapes 0. Fix: add `secrets` get verb to TA ClusterRole, or skip operator SM (KPS being removed). | V1,V8 |
| B3 | 2026-05-01 | `apiserver` SM discovered by TA (job present) but 0 targets allocated. Root cause: `per-node` allocation strategy requires pod-scheduled targets; kube-apiserver runs as Talos static pod on control-plane nodes — no matching OTel collector pod. Additionally SM uses `bearerTokenFile` (file path) which agent may not resolve. Prometheus scrapes 3 apiserver targets; OTel scrapes 0. Fix: scrape apiserver via OTel `k8s_cluster` or `hostmetrics` receiver, or add a static scrape job. | V1,V8 |
| B4 | 2026-05-01 | Blackbox Probe CRs (`probe/monitoring/devices`, `probe/monitoring/nfs`) not present in TA job list. Root cause: `probeSelector` absent from TA config — only `podMonitorSelector`/`serviceMonitorSelector` set. Fix: add `probeSelector: {}` to TA `prometheusCR` block in `otel-agent.yaml`. OTel ⊥ replaces ICMP/TCP_connect probing → blackbox-exporter stays. | V1,V8,V23 |
| B5 | 2026-05-01 | OTel prometheus receiver (TargetAllocator) maps `job` scrape label → `service.name` resource attribute; VMSingle receives `service=X`, `job` absent. ∀ PrometheusRule alert expressions filtering `job=` evaluate empty series → alerts inactive. Fix: add `transform/add_job_label` processor in gateway metrics pipeline — copy `attributes["service"]` → `attributes["job"]` when job absent. | V24 |
| B6 | 2026-05-01 | TargetAllocator does not honor ServiceMonitor `spec.jobLabel` — job name stays as SM name (e.g. `kube-prometheus-stack-kubelet`) instead of resolving via jobLabel `k8s-app` → `kubelet`. Prometheus applies jobLabel relabeling; OTel TA does not. Result: VMSingle has `job="kube-prometheus-stack-kubelet"`, PrometheusRules expect `job="kubelet"` → KubeletDown false-fires, kubelet-specific recording rules miss. Fix: add `metricstransform` or `transform` processor to rename job values, or patch TA to honor jobLabel. | V24,V1 |
