#!/usr/bin/env bash
set -euo pipefail

# Always run relative to this script's directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Load env from this folder
ENV_FILE="$DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (copy .env.example to .env)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

# Use the kubeconfig from .env for all kubectl commands
export KUBECONFIG="${KUBECONFIG_FILE}"

# Safety: remove any old Grafana service in default namespace that blocks NodePort 32000
kubectl -n default delete svc grafana --ignore-not-found

# Required variables (fail fast if any are missing/empty)
need_vars=( NAMESPACE KUBECONFIG_FILE
  FETCHER_APP_NAME FETCHER_IMAGE FETCHER_TAG FETCHER_CONTAINER_PORT FETCHER_REPLICAS
  NEWS_APP_NAME NEWS_IMAGE NEWS_TAG NEWS_CONTAINER_PORT NEWS_REPLICAS
  INFLUXDB_IMAGE INFLUXDB_STORAGE_SIZE INFLUXDB_ADMIN_USER INFLUXDB_ADMIN_PASSWORD INFLUXDB_ORG INFLUXDB_BUCKET INFLUXDB_RETENTION
  GRAFANA_IMAGE GRAFANA_STORAGE_SIZE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
  INFLUXDB_ADMIN_TOKEN
)
for v in "${need_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "Missing required var in .env: $v"; exit 1; }
done

render_globals() {
  sed -e "s/{{NAMESPACE}}/$NAMESPACE/g"
}

render_fetcher() {
  sed \
    -e "s/{{FETCHER_APP_NAME}}/$FETCHER_APP_NAME/g" \
    -e "s#{{FETCHER_IMAGE}}#$FETCHER_IMAGE#g" \
    -e "s/{{FETCHER_TAG}}/$FETCHER_TAG/g" \
    -e "s/{{FETCHER_CONTAINER_PORT}}/$FETCHER_CONTAINER_PORT/g" \
    -e "s/{{FETCHER_REPLICAS}}/$FETCHER_REPLICAS/g"
}

render_news() {
  sed \
    -e "s/{{NEWS_APP_NAME}}/$NEWS_APP_NAME/g" \
    -e "s#{{NEWS_IMAGE}}#$NEWS_IMAGE#g" \
    -e "s/{{NEWS_TAG}}/$NEWS_TAG/g" \
    -e "s/{{NEWS_CONTAINER_PORT}}/$NEWS_CONTAINER_PORT/g" \
    -e "s/{{NEWS_REPLICAS}}/$NEWS_REPLICAS/g"
}

render_influx() {
  sed \
    -e "s/{{INFLUXDB_STORAGE_SIZE}}/$INFLUXDB_STORAGE_SIZE/g" \
    -e "s#{{INFLUXDB_IMAGE}}#$INFLUXDB_IMAGE#g" \
    -e "s/{{INFLUXDB_ORG}}/$INFLUXDB_ORG/g" \
    -e "s/{{INFLUXDB_BUCKET}}/$INFLUXDB_BUCKET/g" \
    -e "s/{{INFLUXDB_RETENTION}}/$INFLUXDB_RETENTION/g"
}

render_grafana() {
  sed \
    -e "s#{{GRAFANA_IMAGE}}#$GRAFANA_IMAGE#g" \
    -e "s/{{GRAFANA_STORAGE_SIZE}}/$GRAFANA_STORAGE_SIZE/g"
}

# Apply fetcher
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/deployment-fetcher.yaml" | render_fetcher)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/service-fetcher.yaml"     | render_fetcher)

# Apply news
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/deployment-news.yaml" | render_news)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/service-news.yaml"     | render_news)

# InfluxDB
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/influxdb-pvc.yaml"         | render_influx)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/influxdb-secret.tmpl.yaml" | render_influx \
  | sed -e "s/{{INFLUXDB_ADMIN_USER}}/$INFLUXDB_ADMIN_USER/g" \
        -e "s/{{INFLUXDB_ADMIN_PASSWORD}}/$INFLUXDB_ADMIN_PASSWORD/g" \
        -e "s/{{INFLUXDB_ORG}}/$INFLUXDB_ORG/g" \
        -e "s/{{INFLUXDB_BUCKET}}/$INFLUXDB_BUCKET/g" \
        -e "s/{{INFLUXDB_RETENTION}}/$INFLUXDB_RETENTION/g" \
        -e "s/{{INFLUXDB_ADMIN_TOKEN}}/$INFLUXDB_ADMIN_TOKEN/g" )
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/influxdb-deployment.yaml"  | render_influx)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/influxdb-service.yaml")

# Grafana
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-pvc.yaml"          | render_grafana)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-secret.tmpl.yaml"  \
  | sed -e "s/{{GRAFANA_ADMIN_USER}}/$GRAFANA_ADMIN_USER/g" \
        -e "s/{{GRAFANA_ADMIN_PASSWORD}}/$GRAFANA_ADMIN_PASSWORD/g" )
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-datasource.yaml"   \
  | sed -e "s/{{INFLUXDB_ORG}}/$INFLUXDB_ORG/g" -e "s/{{INFLUXDB_BUCKET}}/$INFLUXDB_BUCKET/g" )
# Dashboards provisioning (namespace templated)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-provisioning-dashboards.yaml")
# Dashboards content (namespace templated)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-dashboards.yaml")

# Deployment & service last (after CMs exist)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-deployment.yaml"   | render_grafana)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-service.yaml")

# --- Force Grafana to re-provision dashboards/datasources each run ---
kubectl -n "$NAMESPACE" rollout restart deploy/grafana
kubectl -n "$NAMESPACE" rollout status  deploy/grafana --timeout=180s || true

# --- Friendly status ---
echo "Grafana should be reachable at: http://${K3S_NODE_IP:-192.168.56.102}:32000"
kubectl -n "$NAMESPACE" get svc grafana
# Ensure fetcher has TICKERS env
if [[ -n "${TICKERS:-}" ]]; then
  kubectl -n "$NAMESPACE" set env deploy/stockops-fetcher TICKERS="${TICKERS}" || true
fi

echo "Applied deployments & services for fetcher and news in $NAMESPACE."

