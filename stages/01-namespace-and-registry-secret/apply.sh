#!/usr/bin/env bash
set -euo pipefail

# Load env
ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill values." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DOCKERHUB_USERNAME:?Missing DOCKERHUB_USERNAME}"
: "${DOCKERHUB_PASSWORD:?Missing DOCKERHUB_PASSWORD}"
: "${DOCKERHUB_EMAIL:?Missing DOCKERHUB_EMAIL}"
: "${KUBECONFIG_FILE:?Missing KUBECONFIG_FILE}"

# 1) Namespace
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f "$(dirname "$0")/namespace.yaml"

# 2) Docker Hub secret (idempotent via apply)
KUBECONFIG="$KUBECONFIG_FILE" kubectl -n ci create secret docker-registry dockerhub \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="${DOCKERHUB_USERNAME}" \
  --docker-password="${DOCKERHUB_PASSWORD}" \
  --docker-email="${DOCKERHUB_EMAIL}" \
  --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_FILE" kubectl -n ci apply -f -

echo "Stage 01 applied."
