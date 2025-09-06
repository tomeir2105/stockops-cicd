#!/usr/bin/env bash
set -euo pipefail

# Structured logging
LOG_FILE="${LOG_FILE:-one_shot_$(date +%Y%m%d_%H%M%S).log}"
exec > >(tee -a "$LOG_FILE") 2>&1

# nicer xtrace with timestamps (toggle with TRACE=1 ./one_shot.sh)
if [[ "${TRACE:-0}" == "1" ]]; then
  export PS4='+ [${EPOCHREALTIME}] ${BASH_SOURCE##*/}:${LINENO}: ${FUNCNAME[0]:-main} > '
  set -x
fi

on_err() {
  local exit_code=$?
  echo "$(ts) ERROR: command failed at ${BASH_SOURCE##*/}:${BASH_LINENO[0]} — '${BASH_COMMAND}'"
  echo "$(ts) Gathering last events/pods:"
  kubectl -n "${NAMESPACE}" get pods -o wide || true
  kubectl -n "${NAMESPACE}" get events --sort-by=.lastTimestamp | tail -n 60 || true
  echo "$(ts) Log tail (grafana):"
  kubectl -n "${NAMESPACE}" logs deploy/grafana --tail=120 || true
  exit $exit_code
}
trap on_err ERR

# ------------ Config ------------
# Load local parameters if set_params.sh exists
if [[ -f "$(dirname "$0")/secret_params.sh" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/secret_params.sh"
fi

K3S_HOST="${K3S_HOST:-user@192.168.56.102}"
K3S_IP="${K3S_IP:-192.168.56.102}"
KUBECONFIG_FILE="${KUBECONFIG_FILE:-$(pwd)/k3s-jenkins.yaml}"
NAMESPACE="${NAMESPACE:-ci}"

CICD_REPO="${CICD_REPO:-https://github.com/tomeir2105/stockops-cicd.git}"
CICD_BRANCH="${CICD_BRANCH:-main}"
APP_REPO="${APP_REPO:-https://github.com/tomeir2105/stockops.git}"
APP_BRANCH="${APP_BRANCH:-main}"

DOCKERHUB_USER="${DOCKERHUB_USER:-meir25}"
DOCKERHUB_PAT="${DOCKERHUB_PAT:-}"
FETCHER_IMAGE="${FETCHER_IMAGE:-docker.io/${DOCKERHUB_USER}/stockops-fetcher}"
FETCHER_TAG="${FETCHER_TAG:-latest}"
NEWS_IMAGE="${NEWS_IMAGE:-docker.io/${DOCKERHUB_USER}/stockops-news}"
NEWS_TAG="${NEWS_TAG:-latest}"

INFLUXDB_ADMIN_USER="${INFLUXDB_ADMIN_USER:-admin}"
INFLUXDB_ADMIN_PASSWORD="${INFLUXDB_ADMIN_PASSWORD:-changeme}"
INFLUXDB_ORG="${INFLUXDB_ORG:-stockops}"
INFLUXDB_BUCKET="${INFLUXDB_BUCKET:-metricks}"
INFLUXDB_RETENTION="${INFLUXDB_RETENTION:-3d}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-changeme}"
GRAFANA_NODEPORT="${GRAFANA_NODEPORT:-32000}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Hardcode sudo password as requested (for remote sudo)
K3S_SUDO_PASS="${K3S_SUDO_PASS:-user}"

# ------------ Helpers ------------
ts() { date +"[%Y-%m-%d %H:%M:%S]"; }
log(){ printf "\n\033[1;36m%s ==> %s\033[0m\n" "$(ts)" "$*"; }
die(){ echo "$(ts) ERROR: $*" >&2; exit 1; }

need_bin(){ command -v "$1" >/dev/null 2>&1 || die "Missing binary: $1"; }

# ------------ Pre-flight ------------
need_bin kubectl
need_bin ssh
need_bin scp
[[ -n "${DOCKERHUB_PAT}" ]] || die "Set DOCKERHUB_PAT env with your Docker Hub access token."
log "Env snapshot (secrets masked)"
echo "NAMESPACE=${NAMESPACE}"
echo "K3S_IP=${K3S_IP}  K3S_HOST=${K3S_HOST}"
echo "DOCKERHUB_USER=${DOCKERHUB_USER}"
echo "DOCKERHUB_PAT=${DOCKERHUB_PAT:+***SET***}"
echo "GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}  GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:+***SET***}"

log "kubectl context"
kubectl config current-context || true
kubectl cluster-info || true

# ------------ 0) Prep k3s VM ------------
log "Ensuring k3s API binds on ${K3S_IP} and fetching kubeconfig"

ssh ${SSH_OPTS} "${K3S_HOST}" "set -euo pipefail
  mkdir -p /tmp
  cat >/tmp/k3s-config.yaml <<'CFG'
write-kubeconfig-mode: \"0644\"
tls-san:
  - ${K3S_IP}
CFG
  printf '%s\n' '${K3S_SUDO_PASS}' | sudo -S install -m 0644 /tmp/k3s-config.yaml /etc/rancher/k3s/config.yaml
  printf '%s\n' '${K3S_SUDO_PASS}' | sudo -S systemctl restart k3s
"

scp ${SSH_OPTS} "${K3S_HOST}:/etc/rancher/k3s/k3s.yaml" "${KUBECONFIG_FILE}" || die "Could not scp kubeconfig"
sed -i "s#server: https://[^:]*:6443#server: https://${K3S_IP}:6443#" "${KUBECONFIG_FILE}"

export KUBECONFIG="${KUBECONFIG_FILE}"
kubectl version || true
kubectl get nodes -o wide || true

# ------------ 1) Locate or clone CI/CD repo ------------
REPO_DIR=""
if [[ -d "./stages/02-kaniko-build" && -f "./stages/03-k8s-deploy/apply.sh" ]]; then
  REPO_DIR="$PWD"
  log "Detected existing CI/CD layout in current directory."
else
  REPO_DIR="$PWD/_cicd"
  if [[ -d "$REPO_DIR/.git" ]]; then
    log "Updating existing clone at $REPO_DIR"
    git -C "$REPO_DIR" fetch --all
    git -C "$REPO_DIR" checkout "${CICD_BRANCH}"
    git -C "$REPO_DIR" pull --ff-only
  else
    log "Cloning CI/CD repo ${CICD_REPO}@${CICD_BRANCH} to $REPO_DIR"
    rm -rf "$REPO_DIR"
    git clone -b "${CICD_BRANCH}" "${CICD_REPO}" "$REPO_DIR"
  fi
fi

# Define stage paths relative to REPO_DIR
STAGE02="$REPO_DIR/stages/02-kaniko-build"
STAGE03="$REPO_DIR/stages/03-k8s-deploy"
STAGE03B="$REPO_DIR/stages/03b-expose-grafana"

[[ -f "$STAGE02/kaniko-build-fetcher.yaml" ]] || die "Missing $STAGE02/kaniko-build-fetcher.yaml"
[[ -f "$STAGE03/apply.sh" ]] || die "Missing $STAGE03/apply.sh"

# ------------ 2) Clean namespace ------------
log "Cleaning namespace ${NAMESPACE}"
kubectl delete ns "${NAMESPACE}" --ignore-not-found
kubectl wait ns "${NAMESPACE}" --for=delete --timeout=120s || true
kubectl create ns "${NAMESPACE}"

# ------------ 3) Docker registry secrets ------------
log "Creating Docker Hub secrets"
kubectl -n "${NAMESPACE}" delete secret regcred docker-config --ignore-not-found
kubectl -n "${NAMESPACE}" create secret docker-registry regcred \
  --docker-username="${DOCKERHUB_USER}" \
  --docker-password="${DOCKERHUB_PAT}" \
  --docker-email="none@none.local" \
  --docker-server="https://index.docker.io/v1/"

tmpd=$(mktemp -d)
cat >"$tmpd/config.json" <<JSON
{"auths":{"https://index.docker.io/v1/":{"auth":"$(printf "%s:%s" "$DOCKERHUB_USER" "$DOCKERHUB_PAT" | base64 -w0)"}}}
JSON
kubectl -n "${NAMESPACE}" create secret generic docker-config --from-file=config.json="$tmpd/config.json"

# ------------ 4) Kaniko build (fetcher) ------------
log "Launching Kaniko build for fetcher image ${FETCHER_IMAGE}:${FETCHER_TAG}"
KANIKO_YAML="$STAGE02/kaniko-build-fetcher.yaml"
tmp=$(mktemp)
sed -e "s|__HTTPS_URL__|${APP_REPO}|g" \
    -e "s|__BRANCH__|${APP_BRANCH}|g" \
    -e "s|__DEST_IMAGE__|${FETCHER_IMAGE}:${FETCHER_TAG}|g" \
    "$KANIKO_YAML" > "$tmp"
kubectl apply -f "$tmp"
rm -f "$tmp"

kubectl -n "${NAMESPACE}" wait --for=condition=complete job/kaniko-build-fetcher --timeout=1200s || true
kubectl -n "${NAMESPACE}" logs job/kaniko-build-fetcher --all-containers=true || true

# ------------ 5) Deploy apps ------------
log "Writing .env for deploy"
cat > "$STAGE03/.env" <<EOF
NAMESPACE=${NAMESPACE}
KUBECONFIG_FILE=${KUBECONFIG_FILE}
FETCHER_APP_NAME=stockops-fetcher
FETCHER_IMAGE=${FETCHER_IMAGE}
FETCHER_TAG=${FETCHER_TAG}
FETCHER_CONTAINER_PORT=8000
FETCHER_REPLICAS=1
NEWS_APP_NAME=stockops-news
NEWS_IMAGE=${NEWS_IMAGE}
NEWS_TAG=${NEWS_TAG}
NEWS_CONTAINER_PORT=8000
NEWS_REPLICAS=1
INFLUXDB_IMAGE=influxdb:2.7
INFLUXDB_STORAGE_SIZE=5Gi
INFLUXDB_ADMIN_USER=${INFLUXDB_ADMIN_USER}
INFLUXDB_ADMIN_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}
INFLUXDB_ORG=${INFLUXDB_ORG}
INFLUXDB_BUCKET=${INFLUXDB_BUCKET}
INFLUXDB_RETENTION=${INFLUXDB_RETENTION}
GRAFANA_IMAGE=grafana/grafana:11.3.0
GRAFANA_STORAGE_SIZE=5Gi
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOF

log "Applying deployments/services"
bash "$STAGE03/apply.sh"

# ------------ 6) Expose Grafana ------------
log "Exposing Grafana on NodePort ${GRAFANA_NODEPORT}"
NAMESPACE="${NAMESPACE}" bash "$STAGE03B/run.sh"

ssh ${SSH_OPTS} "${K3S_HOST}" "printf '%s\n' '${K3S_SUDO_PASS}' | sudo -S ufw status | grep -q inactive || printf '%s\n' '${K3S_SUDO_PASS}' | sudo -S ufw allow ${GRAFANA_NODEPORT}/tcp || true"

# ------------ 7) Provision Grafana dashboards ------------
log "Provisioning Grafana dashboards"
[[ -f "$STAGE03/grafana-provisioning-dashboards.yaml" ]] || die "Missing $STAGE03/grafana-provisioning-dashboards.yaml"
[[ -f "$STAGE03/grafana-dashboards.yaml" ]] || die "Missing $STAGE03/grafana-dashboards.yaml"

log "Restarting Grafana to load dashboards"
kubectl -n "${NAMESPACE}" rollout restart deploy/grafana
kubectl -n "${NAMESPACE}" rollout status deploy/grafana --timeout=180s || true

# ------------ 8) Verify ------------
kubectl -n "${NAMESPACE}" rollout status deploy/influxdb --timeout=180s || true
kubectl -n "${NAMESPACE}" rollout status deploy/grafana  --timeout=180s || true
kubectl -n "${NAMESPACE}" rollout status deploy/stockops-fetcher --timeout=180s || true
kubectl -n "${NAMESPACE}" rollout status deploy/stockops-news    --timeout=180s || true

kubectl -n "${NAMESPACE}" get pods -o wide
kubectl -n "${NAMESPACE}" get svc

log "Done. Grafana available at: http://${K3S_IP}:${GRAFANA_NODEPORT} (user=${GRAFANA_ADMIN_USER})"

