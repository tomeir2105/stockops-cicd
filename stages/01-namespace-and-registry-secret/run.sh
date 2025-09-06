#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ci}"

echo "[01] Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# If you need a registry secret for private images, uncomment and edit:
# kubectl -n "$NAMESPACE" create secret docker-registry regcred \
#   --docker-server=<your-registry> \
#   --docker-username=<your-username> \
#   --docker-password=<your-password> \
#   --docker-email=<your-email> \
#   --dry-run=client -o yaml | kubectl apply -f -
