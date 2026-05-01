#!/usr/bin/env bash
# T1: Verify VMSingle receives all key metric series (V1, V4a)
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export ROOT_DIR="$(git rev-parse --show-toplevel)"
LOCAL_PORT=18429
PF_PID=""

cleanup() {
    [[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true
}
trap cleanup EXIT

log info "Starting port-forward to vmsingle-metrics:8429 → localhost:${LOCAL_PORT}"
lsof -ti:"${LOCAL_PORT}" 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
kubectl port-forward svc/vmsingle-metrics "${LOCAL_PORT}:8429" -n monitoring &>/dev/null &
PF_PID=$!
sleep 4

BASE="http://localhost:${LOCAL_PORT}"

log info "Querying VMSingle for all metric names..."
ALL_METRICS="$(curl -sf "${BASE}/api/v1/label/__name__/values" | jq -r '.data[]' 2>/dev/null)" || {
    log error "Failed to query VMSingle — is port-forward running?"
    exit 1
}

PASS=0
FAIL=0

check_prefix() {
    local label="${1}"
    local prefix="${2}"
    if grep -q "^${prefix}" <<< "${ALL_METRICS}"; then
        log info "PASS  ${label} (prefix: ${prefix})"
        (( PASS++ )) || true
    else
        log warn "FAIL  ${label} (prefix: ${prefix})"
        (( FAIL++ )) || true
    fi
}

echo ""
echo "=== VMSingle metric family verification (T1: V1, V4a) ==="
echo ""
echo "--- ServiceMonitor scrape via OTel TargetAllocator ---"

# node-exporter (ServiceMonitor: monitoring/node-exporter)
check_prefix "node-exporter / cpu"    "node_cpu_"
check_prefix "node-exporter / memory" "node_memory_"
check_prefix "node-exporter / disk"   "node_disk_"
check_prefix "node-exporter / fs"     "node_filesystem_"
check_prefix "node-exporter / net"    "node_network_"

# kube-state-metrics (ServiceMonitor: monitoring/kube-state-metrics)
check_prefix "kube-state-metrics / node"       "kube_node_"
check_prefix "kube-state-metrics / pod"        "kube_pod_"
check_prefix "kube-state-metrics / deployment" "kube_deployment_"
check_prefix "kube-state-metrics / daemonset"  "kube_daemonset_"

# kube-apiserver (ServiceMonitor: monitoring/kube-prometheus-stack-apiserver)
check_prefix "kube-apiserver" "apiserver_request_"

# kubelet / cadvisor (ServiceMonitor: monitoring/kube-prometheus-stack-kubelet)
check_prefix "kubelet / cadvisor / container" "container_cpu_"
check_prefix "kubelet / cadvisor / memory"    "container_memory_"

# app ServiceMonitors / PodMonitors
check_prefix "speedtest-exporter" "speedtest_"
check_prefix "envoy-gateway"      "envoy_"
check_prefix "ceph-mgr"           "ceph_"
check_prefix "coredns"            "coredns_"
check_prefix "cilium-agent"       "cilium_"
check_prefix "authentik"          "authentik_"

echo ""
echo "--- OTel collector self-metrics ---"
check_prefix "otel-collector" "otelcol_"

echo ""
echo "=== Results: ${PASS} PASS / ${FAIL} FAIL ==="
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo "Blocking gaps (must fix before Prometheus removal):"
    echo "  B1. kube-state-metrics (kube_*): gRPC 4MB limit on agent→gateway OTLP export"
    echo "      → ~21k items dropped per batch; kube-state-metrics payload too large"
    echo "      Fix: raise grpc_max_recv_msg_size on gateway OR add batch processor to agent"
    echo "  B2. kubelet / cadvisor (container_*): same gRPC limit + TLS auth failures"
    echo "      → scrape of https://NODE_IP:10250 failing; verify kubelet TLS config on OTel agent"
    echo ""
    echo "Note: dragonfly-operator exposes no Prometheus metrics (non-blocking, absent in both stacks)"
    echo ""
    log warn "T1 FAIL — metric gaps exist, DO NOT proceed with removals (V1, V4a not satisfied)"
    exit 1
fi

log info "T1 PASS — all metric families confirmed in VMSingle (V1, V4a satisfied)"
