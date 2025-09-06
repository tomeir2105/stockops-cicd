#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ci}"

echo "[01] Creating namespace and Docker registry secret in $NAMESPACE"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" delete secret regcred --ignore-not-found

kubectl -n "$NAMESPACE" create secret docker-registry regcred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="meir25" \
  --docker-password="${DOCKERHUB_PAT:-CHANGE_ME}" \
  --docker-email="tomeir2105@gmail.com"

