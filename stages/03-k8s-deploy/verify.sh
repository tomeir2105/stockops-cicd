#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/.env"

for v in NAMESPACE KUBECONFIG_FILE FETCHER_APP_NAME NEWS_APP_NAME; do
  [[ -n "${!v:-}" ]] || { echo "Missing $v in .env"; exit 1; }
done

echo "=== Deployments ==="
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get deploy "$FETCHER_APP_NAME" "$NEWS_APP_NAME" -o wide || true

echo "=== Pods (fetcher) ==="
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get pods -l app="$FETCHER_APP_NAME" -o wide || true

echo "=== Pods (news) ==="
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get pods -l app="$NEWS_APP_NAME" -o wide || true

echo "=== Services ==="
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get svc "$FETCHER_APP_NAME" "$NEWS_APP_NAME" -o wide || true

