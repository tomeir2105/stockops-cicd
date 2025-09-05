#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${GIT_URL:?Missing GIT_URL}"
: "${GIT_REF:?Missing GIT_REF}"
: "${DOCKER_IMAGE:?Missing DOCKER_IMAGE}"
: "${DOCKER_TAG:?Missing DOCKER_TAG}"
: "${NAMESPACE:?Missing NAMESPACE}"
: "${KUBECONFIG_FILE:?Missing KUBECONFIG_FILE}"
: "${DOCKERFILE_PATH:?Missing DOCKERFILE_PATH}"
: "${CONTEXT_SUBPATH:?Missing CONTEXT_SUBPATH}"


# Ensure namespace exists (idempotent)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f "$DIR/../01-namespace-and-registry-secret/namespace.yaml"

# ServiceAccount (idempotent)
KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f "$DIR/kaniko-serviceaccount.yaml"

JOB_NAME=kaniko-build-stockops

cat <<YAML | KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NAMESPACE" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: kaniko-builder
      restartPolicy: Never
      volumes:
        - name: src
          emptyDir: {}
        - name: docker-config
          secret:
            secretName: dockerhub
            items:
              - key: .dockerconfigjson
                path: config.json
      initContainers:
        - name: git-clone
          image: alpine/git:latest
          command: ["sh","-c"]
          args:
            - |
              set -eux
              git clone --depth=1 --branch "${GIT_REF}" "${GIT_URL}" /workspace/src
              echo "=== ls -la /workspace/src ==="
              ls -la /workspace/src
              echo "=== find /workspace/src (maxdepth 2) ==="
              find /workspace/src -maxdepth 2 -mindepth 1 -print
          volumeMounts:
            - name: src
              mountPath: /workspace/src
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - "--context=/workspace/src/${CONTEXT_SUBPATH}"
            - "--dockerfile=/workspace/src/${DOCKERFILE_PATH}"
            - "--destination=${DOCKER_IMAGE}:${DOCKER_TAG}"
            - "--verbosity=info"
            - "--snapshot-mode=redo"
            - "--use-new-run"
            - "--cleanup"
          volumeMounts:
            - name: src
              mountPath: /workspace/src
            - name: docker-config
              mountPath: /kaniko/.docker
YAML

echo "Job ${JOB_NAME} applied in namespace ${NAMESPACE}."
echo "Tip: run $DIR/logs.sh to watch logs."

