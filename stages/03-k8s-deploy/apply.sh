#!/usr/bin/env bash
set -euo pipefail

# Resolve script dir even if called via symlink (deploy.sh)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# Load env vars
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "Missing $SCRIPT_DIR/.env (run setup_env.sh first)"; exit 1
fi
set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env"
set +a

# Tools
command -v envsubst >/dev/null 2>&1 || { echo "envsubst missing. Install: sudo apt-get update && sudo apt-get install -y gettext-base"; exit 1; }

# Ensure namespace exists
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Only substitute variables we control; leave Grafana $__env{INFLUXDB_TOKEN} intact
VARS='$NAMESPACE $APP_NAME $FETCHER_APP_NAME $NEWS_APP_NAME $FETCHER_IMAGE $FETCHER_TAG $FETCHER_CONTAINER_PORT $FETCHER_REPLICAS $NEWS_IMAGE $NEWS_TAG $NEWS_CONTAINER_PORT $NEWS_REPLICAS $GRAFANA_IMAGE $GRAFANA_ADMIN_USER $GRAFANA_ADMIN_PASSWORD $GRAFANA_STORAGE_SIZE $INFLUXDB_IMAGE $INFLUXDB_BUCKET $INFLUXDB_ORG $INFLUXDB_ADMIN_TOKEN $INFLUXDB_URL $INFLUXDB_STORAGE_SIZE $INFLUXDB_ADMIN_USER $INFLUXDB_ADMIN_PASSWORD $INFLUXDB_RETENTION $IMAGE $TAG $CONTAINER_PORT $REPLICAS'

# Gather YAMLs (folder + optional manifests/)
mapfile -t SRC_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) -print)
if [[ -d "$SCRIPT_DIR/manifests" ]]; then
  while IFS= read -r f; do SRC_FILES+=("$f"); done < <(find "$SCRIPT_DIR/manifests" -type f \( -name "*.yaml" -o -name "*.yml" \) -print)
fi
[[ ${#SRC_FILES[@]} -gt 0 ]] || { echo "No YAML files found under $SCRIPT_DIR (or ./manifests)."; exit 1; }

# Render each file:
# 1) convert {{VAR}} -> ${VAR} for ALLCAPS placeholders
# 2) envsubst with our whitelist
for f in "${SRC_FILES[@]}"; do
  perl -pe 's/\{\{\s*([A-Z0-9_]+)\s*\}\}/\$\{$1\}/g' "$f" \
  | envsubst "$VARS" \
  > "$TMPDIR/$(basename "$f")"
done

# Normalize/sanitize the rendered YAMLs

# (a) replicas must be int (not quoted)
for g in "$TMPDIR"/*.y*ml; do sed -i -E 's/^( *replicas: *)"([0-9]+)"/\1\2/' "$g"; done

# (b) if any variable accidentally appeared as a KEY, fix to the expected key name
#    ${NAMESPACE}: -> namespace: "${NAMESPACE}"
sed -i -E 's/^([[:space:]]*)\$\{NAMESPACE\}[[:space:]]*:/\1namespace: "${NAMESPACE}"/' "$TMPDIR"/*.y*ml
#    ${APP_NAME}: -> app: "${APP_NAME}"
sed -i -E 's/^([[:space:]]*)\$\{APP_NAME\}[[:space:]]*:/\1app: "${APP_NAME}"/' "$TMPDIR"/*.y*ml
#    ${FETCHER_APP_NAME}: -> app: "${FETCHER_APP_NAME}"
sed -i -E 's/^([[:space:]]*)\$\{FETCHER_APP_NAME\}[[:space:]]*:/\1app: "${FETCHER_APP_NAME}"/' "$TMPDIR"/*.y*ml
#    ${NEWS_APP_NAME}: -> app: "${NEWS_APP_NAME}"
sed -i -E 's/^([[:space:]]*)\$\{NEWS_APP_NAME\}[[:space:]]*:/\1app: "${NEWS_APP_NAME}"/' "$TMPDIR"/*.y*ml

# (c) fail fast if any placeholders remain to avoid feeding bad YAML to kubectl
if grep -R '\${[A-Z0-9_]\+}' "$TMPDIR" >/dev/null; then
  echo "[ERROR] Unsubstituted placeholders remain in rendered files:"
  grep -Rn '\${[A-Z0-9_]\+}' "$TMPDIR" || true
  echo "Check your .env has values for all referenced variables above."
  exit 1
fi
if grep -R '{{[A-Z0-9_]\+}}' "$TMPDIR" >/dev/null; then
  echo "[ERROR] Curly placeholders {{VAR}} remain in rendered files:"
  grep -Rn '{{[A-Z0-9_]\+}}' "$TMPDIR" || true
  exit 1
fi

# Apply
# Skip PVCs if they already exist (avoid size-downgrade errors)

if kubectl -n "$NAMESPACE" get pvc grafana-data >/dev/null 2>&1; then rm -f "$TMPDIR/grafana-pvc.yaml"; fi

if kubectl -n "$NAMESPACE" get pvc influxdb-data >/dev/null 2>&1; then rm -f "$TMPDIR/influxdb-pvc.yaml"; fi
kubectl -n "$NAMESPACE" apply -f "$TMPDIR"

echo "Applied manifests to namespace '$NAMESPACE'."

