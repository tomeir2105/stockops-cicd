#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# load env vars
if [[ ! -f ./.env ]]; then
  echo "Missing $SCRIPT_DIR/.env (run setup_env.sh first)"; exit 1
fi
set -a
source ./.env
set +a

# ensure namespace exists
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# substitute only known vars
VARS='$NAMESPACE $FETCHER_IMAGE $NEWS_IMAGE $GRAFANA_IMAGE $INFLUXDB_IMAGE $TICKERS $NEWS_KEYWORDS $GRAFANA_ADMIN_USER $GRAFANA_ADMIN_PASSWORD $INFLUXDB_BUCKET $INFLUXDB_ORG $INFLUXDB_TOKEN $INFLUXDB_ADMIN_TOKEN $INFLUXDB_URL'

for f in *.yaml *.yml; do
  [[ -f "$f" ]] || continue
  envsubst "$VARS" < "$f" > "$TMPDIR/$(basename "$f")"
done

kubectl -n "$NAMESPACE" apply -f "$TMPDIR"

echo "Applied manifests to namespace '$NAMESPACE'."

