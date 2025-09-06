#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ci}"
IMAGE="${IMAGE:-meir25/stockops-app:latest}"

echo "[02-kaniko-build] Building image $IMAGE in namespace $NAMESPACE (using local context)"

# Delete old job if exists
kubectl -n "$NAMESPACE" delete job kaniko-build --ignore-not-found

# Create ConfigMap from local repo
kubectl -n "$NAMESPACE" delete configmap stockops-src --ignore-not-found
kubectl -n "$NAMESPACE" create configmap stockops-src --from-file=.

# Kaniko job mounting the configmap
kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-build
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:latest
        args:
          - --dockerfile=/workspace/Dockerfile
          - --context=/workspace
          - --destination=$IMAGE
        volumeMounts:
          - name: context
            mountPath: /workspace
          - name: kaniko-secret
            mountPath: /kaniko/.docker
      volumes:
        - name: context
          configMap:
            name: stockops-src
        - name: kaniko-secret
          secret:
            secretName: regcred
YAML

kubectl -n "$NAMESPACE" wait --for=condition=complete job/kaniko-build --timeout=600s

