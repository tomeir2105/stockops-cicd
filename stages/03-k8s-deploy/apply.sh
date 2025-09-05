#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (copy .env.example to .env)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

for v in NAMESPACE APP_NAME IMAGE TAG CONTAINER_PORT REPLICAS KUBECONFIG_FILE; do
  [[ -n "${!v:-}" ]] || { echo "Missing $v in .env"; exit 1; }
done

render() {
  sed \
    -e "s/{{NAMESPACE}}/$NAMESPACE/g" \
    -e "s/{{APP_NAME}}/$APP_NAME/g" \
    -e "s#{{IMAGE}}#$IMAGE#g" \
    -e "s/{{TAG}}/$TAG/g" \
    -e "s/{{CONTAINER_PORT}}/$CONTAINER_PORT/g" \
    -e "s/{{REPLICAS}}/$REPLICAS/g"
}

KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render < "$DIR/deployment.yaml")
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render < "$DIR/service.yaml")

echo "Applied deployment & service for $APP_NAME in $NAMESPACE."

