#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${KUBECONFIG_FILE:?Missing KUBECONFIG_FILE}"

KUBECONFIG="$KUBECONFIG_FILE" kubectl get ns ci
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n ci get secret dockerhub -o yaml | grep -E 'name: dockerhub|type: kubernetes.io/dockerconfigjson'
echo "Stage 01 verify OK."
