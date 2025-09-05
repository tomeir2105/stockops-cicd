#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/.env"
for v in NAMESPACE APP_NAME KUBECONFIG_FILE; do
  [[ -n "${!v:-}" ]] || { echo "Missing $v in .env"; exit 1; }
done

KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get deploy "$APP_NAME" -o wide
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" get svc "$APP_NAME" -o wide

