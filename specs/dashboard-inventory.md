# Dashboard Inventory (T8 — 2026-05-03)

| dashboard | source | folder | datasource | action |
|---|---|---|---|---|
| blackbox-exporter (13659) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| cert-manager (20842) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| cloudflared (17457) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| speedtest-exporter (13665) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| external-dns (15038) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| external-secrets (URL) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| node-exporter-full (1860) | helmrelease | default | Prometheus | drop — superseded by VM community (T9) |
| volsync (21356) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| zfs (7845) | helmrelease | default | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| ceph-cluster (2842) | helmrelease | Ceph | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| ceph-osd (5336) | helmrelease | Ceph | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| ceph-pools (5342) | helmrelease | Ceph | Prometheus | convert → ConfigMap, DS: VictoriaMetrics |
| flux-cluster (URL) | helmrelease | Flux | Prometheus | drop — replaced by T10 hand-written LogsQL |
| flux-control-plane (URL) | helmrelease | Flux | Prometheus | drop — replaced by T10 hand-written LogsQL |
| k8s-system-api-server (15761) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| k8s-views-global (15757) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| k8s-views-nodes (15759) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| k8s-views-namespaces (15758) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| k8s-views-pods (15760) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| k8s-volumes (11454) | helmrelease | Kubernetes | Prometheus | drop — replaced by VM community (T9) |
| home.json | ConfigMap sidecar | (default) | prometheus uid `PBFA97CFB590B2093` | rewrite → VictoriaMetrics (T11) |
| flux-logs.json | ConfigMap sidecar | (via annotation) | VictoriaLogs | done (T10 partial) |
| cloudnative-pg grafanaDashboard | app helm | Postgres | Prometheus | disable/rewrite (T11) |
| spegel grafanaDashboard | app helm | default | Prometheus | disable/rewrite (T11) |

