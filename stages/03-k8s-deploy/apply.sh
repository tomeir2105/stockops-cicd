#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$DIR/.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (copy .env.example to .env)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

need_vars=(NAMESPACE KUBECONFIG_FILE
  FETCHER_APP_NAME FETCHER_IMAGE FETCHER_TAG FETCHER_CONTAINER_PORT FETCHER_REPLICAS
  NEWS_APP_NAME NEWS_IMAGE NEWS_TAG NEWS_CONTAINER_PORT NEWS_REPLICAS)
need_vars+=(INFLUXDB_IMAGE INFLUXDB_STORAGE_SIZE INFLUXDB_ADMIN_USER INFLUXDB_ADMIN_PASSWORD INFLUXDB_ORG INFLUXDB_BUCKET INFLUXDB_RETENTION)
need_vars+=(GRAFANA_IMAGE GRAFANA_STORAGE_SIZE GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD)

for v in "${need_vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "Missing $v in .env"; exit 1; }
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

KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-deployment.yaml"   | render_grafana)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f <(render_globals < "$DIR/grafana-service.yaml")

echo "Applied deployments & services for fetcher and news in $NAMESPACE."

