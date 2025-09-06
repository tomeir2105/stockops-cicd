#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-ci}"
IMAGE="${IMAGE:-meir25/stockops-app:latest}"

echo "[02-kaniko-build] Building image $IMAGE in namespace $NAMESPACE"

# Delete old job if exists
kubectl -n "$NAMESPACE" delete job kaniko-build --ignore-not-found

# Create new job
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
          - --context=git://github.com/tomeir2105/stockops-cicd.git
          - --destination=$IMAGE
        volumeMounts:
          - name: kaniko-secret
            mountPath: /kaniko/.docker
      volumes:
        - name: kaniko-secret
          secret:
            secretName: regcred
YAML

# Wait for job completion
kubectl -n "$NAMESPACE" wait --for=condition=complete job/kaniko-build --timeout=600s

