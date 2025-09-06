#!/bin/bash
set -euo pipefail

NS=ci
YAML=./stages/02-kaniko-build/kaniko-build-fetcher.yaml
DEST_IMAGE="${DEST_IMAGE:-meir25/stockops-fetcher:latest}"

# derive HTTPS URL + branch from current repo
origin=$(git config --get remote.origin.url)
branch=$(git rev-parse --abbrev-ref HEAD)

normalize() {
  local o="$1"
  if [[ "$o" =~ ^git@github\.com:(.+)\.git$ ]]; then
    echo "https://github.com/${BASH_REMATCH[1]}.git"
  elif [[ "$o" =~ ^git@github\.com:(.+)$ ]]; then
    echo "https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$o" =~ ^https?:// ]]; then
    echo "$o"
  else
    echo ""
  fi
}
https_url=$(normalize "$origin"); [[ -n "$https_url" ]] || { echo "Bad origin: $origin"; exit 1; }

# ensure namespace exists
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# clean previous job
kubectl -n "$NS" delete job kaniko-build-fetcher --ignore-not-found

# render placeholders -> temp file and apply
tmp=$(mktemp)
sed -e "s|__HTTPS_URL__|$https_url|g" \
    -e "s|__BRANCH__|$branch|g" \
    -e "s|__DEST_IMAGE__|$DEST_IMAGE|g" \
    "$YAML" > "$tmp"

kubectl apply -f "$tmp"
rm -f "$tmp"

# wait & show logs (best-effort)
kubectl -n "$NS" wait --for=condition=complete job/kaniko-build-fetcher --timeout=900s || true
kubectl -n "$NS" logs job/kaniko-build-fetcher --all-containers=true || true

