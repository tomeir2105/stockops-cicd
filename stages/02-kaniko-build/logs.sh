#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$DIR/.env"
source "$ENV_FILE"
: "${KUBECONFIG_FILE:?Missing KUBECONFIG_FILE}"
: "${NAMESPACE:?Missing NAMESPACE}"

KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" logs job/kaniko-build-stockops -f

