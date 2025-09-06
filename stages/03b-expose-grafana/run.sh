#!/usr/bin/env bash
set -euo pipefail

# ===============================
# 03b-expose-grafana
# Ensures Grafana is exposed via NodePort 32000
# ===============================

NAMESPACE="${NAMESPACE:-ci}"
SVC_FILE="$(dirname "$0")/grafana-service.yaml"

# Use first cluster server from kubeconfig (works even if no current-context)
API_HOST=$(kubectl config view --raw -o jsonpath='{.clusters[*].cluster.server}' | sed -E 's#https?://([^:/]+).*#\1#; q')

# Avoid Jenkins proxy interfering with kubectl
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY="${API_HOST}"

# Ensure correct namespace in the manifest (idempotent)
if command -v gsed >/dev/null 2>&1; then SED=gsed; else SED=sed; fi
$SED -i "s/namespace: .*/namespace: ${NAMESPACE}/" "${SVC_FILE}"

echo "[03b-expose-grafana] Applying NodePort service (selector app=grafana, nodePort=32000)…"
kubectl apply --validate=false -f "${SVC_FILE}"

# Show status & endpoints (helps detect selector mismatch)
kubectl -n "${NAMESPACE}" get svc grafana-nodeport -o wide
kubectl -n "${NAMESPACE}" get endpoints grafana-nodeport -o yaml | sed -n '1,80p' || true

# Print access URL (defaults to API host, override via ACCESS_IP if you want)
ACCESS_IP="${ACCESS_IP:-${API_HOST}}"
echo
echo "[03b-expose-grafana] Access Grafana at:"
echo "  -> http://${ACCESS_IP}:32000"
echo

