#!/usr/bin/env bash
set -euo pipefail

# 03b-expose-grafana: expose Grafana on NodePort 32000 and print URL.

NAMESPACE="${NAMESPACE:-ci}"
SVC_FILE="$(dirname "$0")/grafana-service.yaml"

# Work even if no current-context is set; take the first cluster server:
API_HOST="$(kubectl config view --raw -o jsonpath='{.clusters[*].cluster.server}' | sed -E 's#https?://([^:/]+).*#\1#; q')"

# Keep kubectl off any Jenkins proxy:
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY="${API_HOST}"

# Ensure namespace in manifest matches target namespace (idempotent):
if command -v gsed >/dev/null 2>&1; then SED=gsed; else SED=sed; fi
$SED -i "s/namespace: .*/namespace: ${NAMESPACE}/" "${SVC_FILE}"

echo "[03b] Applying Grafana NodePort service (port 3000 -> nodePort 32000)…"
kubectl apply --validate=false -f "${SVC_FILE}"

# Wait until there is at least one endpoint (selector matches a Ready pod)
echo "[03b] Waiting for Grafana endpoints…"
for i in {1..30}; do
  if kubectl -n "${NAMESPACE}" get endpoints grafana-nodeport -o json \
      | jq -e '.subsets | length > 0' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo
kubectl -n "${NAMESPACE}" get svc grafana-nodeport -o wide || true
kubectl -n "${NAMESPACE}" get endpoints grafana-nodeport -o yaml | sed -n '1,80p' || true
echo

ACCESS_IP="${ACCESS_IP:-${API_HOST}}"
echo "[03b] Access Grafana at:"
echo "  -> http://${ACCESS_IP}:32000"

