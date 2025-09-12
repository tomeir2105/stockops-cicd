#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
DOCKERHUB_USER="meir25"

# Map image names → local build contexts (adjust paths if yours differ)
# If your Dockerfiles are not named 'Dockerfile', add  --file <path>  in docker build lines below.
declare -A IMAGES=(
  ["stockops-fetcher"]="./stockops-fetcher"   # e.g., path to fetcher code
  ["stockops-news"]="./stockops-news"         # e.g., path to news code
  # ["stockops-app"]="./stockops-app"         # uncomment if you want to (re)build/push the UI/api app
)

# --- TAGS ---
GIT_SHA="$(git rev-parse --short HEAD || echo manual)"
DATE_TAG="$(date +%F)"
VERSION_TAG="${GIT_SHA}-${DATE_TAG}"

echo "[i] Version tag: ${VERSION_TAG}"

# --- LOGIN (safe to skip if already logged in) ---
if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not reachable. Is Docker running?"
  exit 1
fi

if ! docker system info 2>/dev/null | grep -q "Username: ${DOCKERHUB_USER}"; then
  echo "[i] Logging in to Docker Hub as ${DOCKERHUB_USER}..."
  docker login -u "${DOCKERHUB_USER}"
fi

# --- BUILD/PUSH LOOP ---
for NAME in "${!IMAGES[@]}"; do
  CTX="${IMAGES[$NAME]}"
  IMAGE="${DOCKERHUB_USER}/${NAME}"

  echo
  echo "=== Building ${IMAGE} from ${CTX} ==="
  docker build \
    --pull \
    --progress=plain \
    -t "${IMAGE}:latest" \
    -t "${IMAGE}:${VERSION_TAG}" \
    "${CTX}"

  echo "[i] Pushing ${IMAGE}:${VERSION_TAG} and :latest"
  docker push "${IMAGE}:${VERSION_TAG}"
  docker push "${IMAGE}:latest"

  echo "[✓] Pushed ${IMAGE} (${VERSION_TAG})"
done

echo
echo "[✓] All images pushed."
echo "[i] Verify on Docker Hub or by pulling:"
for NAME in "${!IMAGES[@]}"; do
  IMAGE="${DOCKERHUB_USER}/${NAME}"
  echo "    docker pull ${IMAGE}:${VERSION_TAG} && docker images ${IMAGE} --digests | head"
done

