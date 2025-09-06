#!/usr/bin/env bash
set -euo pipefail

NS=ci
ENV01=./stages/01-namespace-and-registry-secret/.env
ENV03=./stages/03-k8s-deploy/.env

# --- read envs (DockerHub + image names)
[[ -f "$ENV01" ]] && . "$ENV01" || true
[[ -f "$ENV03" ]] && . "$ENV03" || true

: "${FETCHER_IMAGE:=meir25/stockops-fetcher}"
: "${FETCHER_TAG:=latest}"
: "${NEWS_IMAGE:=meir25/stockops-news}"
: "${NEWS_TAG:=latest}"

# 1) Recreate pull/push secrets (fix 401 Unauthorized / ErrImagePull due to auth)
if [[ -n "${DOCKERHUB_USER:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "[1/6] Recreating Docker secrets..."
  kubectl -n "$NS" delete secret regcred docker-config --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NS" create secret docker-registry regcred \
    --docker-username="$DOCKERHUB_USER" \
    --docker-password="$DOCKERHUB_TOKEN" \
    --docker-email="none@none.local" \
    --docker-server="https://index.docker.io/v1/" >/dev/null
  tmpd=$(mktemp -d)
  cat >"$tmpd/config.json" <<JSON
{"auths":{"https://index.docker.io/v1/":{"username":"$DOCKERHUB_USER","password":"$DOCKERHUB_TOKEN","auth":"$(printf "%s" "$DOCKERHUB_USER:$DOCKERHUB_TOKEN" | base64 -w0)"}}}
JSON
  kubectl -n "$NS" create secret generic docker-config --from-file=config.json="$tmpd/config.json" >/dev/null
  rm -rf "$tmpd"
else
  echo "[1/6] WARN: DOCKERHUB_USER/TOKEN not found in $ENV01; skipping secret refresh."
fi

# 2) Ensure every deployment uses regcred + Always pull
echo "[2/6] Ensuring imagePullSecrets and imagePullPolicy=Always..."
for d in $(kubectl -n "$NS" get deploy -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$NS" patch deploy "$d" --type=merge -p \
    '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}' >/dev/null 2>&1 || true
  # set imagePullPolicy=Always for all containers
  names=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[*].name}')
  for cname in $names; do
    kubectl -n "$NS" patch deploy "$d" --type=json \
      -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"Always\"}]" >/dev/null 2>&1 || true
  done
done

# 3) Point app deployments to the exact images/tags we built
echo "[3/6] Setting images for fetcher/news to ${FETCHER_IMAGE}:${FETCHER_TAG} and ${NEWS_IMAGE}:${NEWS_TAG}..."
kubectl -n "$NS" set image deploy/stockops-fetcher stockops-fetcher="${FETCHER_IMAGE}:${FETCHER_TAG}" >/dev/null 2>&1 || true
kubectl -n "$NS" set image deploy/stockops-news    stockops-news="${NEWS_IMAGE}:${NEWS_TAG}"       >/dev/null 2>&1 || true

# 4) Fix PVC size issues: keep the larger of current vs desired (no shrink)
echo "[4/6] Harmonizing PVC sizes (no shrinking)..."
fix_pvc() {
  local pvc="$1" desired="$2"
  local cur; cur=$(kubectl -n "$NS" get pvc "$pvc" -o jsonpath='{.status.capacity.storage}' 2>/dev/null || true)
  [[ -z "$cur" ]] && return 0
  to_mib() {
    [[ "$1" =~ ^([0-9]+)Gi$ ]] && { echo $(( ${BASH_REMATCH[1]} * 1024 )); return; }
    [[ "$1" =~ ^([0-9]+)Mi$ ]] && { echo ${BASH_REMATCH[1]}; return; }
    echo 0
  }
  cur_mi=$(to_mib "$cur"); des_mi=$(to_mib "$desired")
  if (( cur_mi > 0 && des_mi > 0 && cur_mi > des_mi )); then
    echo "  - $pvc: keeping existing $cur (desired $desired is smaller)"
    # patch deployment env to keep current size next apply (optional)
    sed -i "s/^$(echo "${pvc%%-*}" | tr a-z A-Z)_STORAGE_SIZE=.*/$(echo "${pvc%%-*}" | tr a-z A-Z)_STORAGE_SIZE=$cur/" "$ENV03" 2>/dev/null || true
  fi
}
fix_pvc influxdb-data   "${INFLUXDB_STORAGE_SIZE:-5Gi}"
fix_pvc grafana-data    "${GRAFANA_STORAGE_SIZE:-5Gi}"

# 5) Restart everything cleanly
echo "[5/6] Restarting deployments..."
for d in $(kubectl -n "$NS" get deploy -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$NS" rollout restart deploy "$d" >/dev/null 2>&1 || true
done

# 6) Wait and summarize; if errors, print the reason
echo "[6/6] Waiting for rollouts..."
timeout=300
for d in $(kubectl -n "$NS" get deploy -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$NS" rollout status deploy "$d" --timeout=${timeout}s || true
done

echo "---- Pods ----"
kubectl -n "$NS" get pods -o wide

echo "---- Recent pull errors (if any) ----"
kubectl -n "$NS" get events --sort-by=.lastTimestamp \
  | egrep -i 'imagepull|backoff|unauthor|not found|manifest|dns' || true

echo "Done."

