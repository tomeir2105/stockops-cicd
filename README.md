# StockOps CI/CD (Direct Deploy on k3s)

**Repo:** `tomeir2105/stockops-cicd`  
**Goal:** Build/push your StockOps images locally and **deploy directly** to a k3s cluster using shell scripts and Kubernetes manifests (no Kaniko).

---

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Minimum Requirements](#minimum-requirements)
- [Where to Run](#where-to-run)
- [Installation](#installation)
- [Environment Variables](#environment-variables)
- [Usage](#usage)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)
- [Notes](#notes)

---

## Overview

This repository contains the **CI/CD glue** for the StockOps project. It assumes you build Docker images **locally** (or in your own pipeline) and deploy to a **k3s** cluster using `kubectl` and the manifests under `stages/03-k8s-deploy/`.

Typical flow:
1. Build images locally (e.g., `meir25/stockops-fetcher`, `meir25/stockops-news`) and push to Docker Hub.
2. Run `deploy.sh` (or `one_shot.sh`) from a control machine that has `kubectl` access to your k3s cluster.
3. Access **Grafana** via NodePort to view dashboards.

> Examples below use `192.168.56.102` as the k3s node IP and `ci` as the namespace. Adjust to your setup.

---

## Architecture

```
Local dev / CI (build + push Docker images)
        │
        └──> Docker Hub (e.g., meir25/* images)
                  │
                  └──> k3s cluster (e.g., 192.168.56.102)
                          ├─ Namespace: ci
                          ├─ Deployments: stockops-fetcher, stockops-news, influxdb, grafana
                          └─ Services: Grafana exposed via NodePort 32000
```

---

## Repository Structure

```
.
├── .gitignore
├── .pf-grafana.pid           # (optional/ephemeral) created by port-forward helper
├── Dockerfile                # Base Dockerfile (not Kaniko)
├── README.md                 # This file (recommended replacement)
├── deploy.sh                 # Main direct-deploy script to the cluster
├── env                       # Example env file or placeholder (do not commit secrets)
├── one_shot.sh               # All-in-one helper (reset + deploy); uses direct apply
├── stabilize-ci.sh           # Namespace cleanup/stabilization
├── sync_images.sh            # Optional helper to sync/push images
└── stages/
    └── 03-k8s-deploy/        # Kubernetes manifests (deployments, services, secrets templates, dashboards)
```

> The **only active stage** is `03-k8s-deploy/`. Older Kaniko stages were removed from the flow.

---

## Minimum Requirements

**Control Host (where you run the scripts):**
- Linux (Ubuntu 22.04+ recommended)
- CPU: 2+ cores
- RAM: 4 GB+
- Disk: 10 GB free
- Tools: `bash`, `git`, `kubectl`, `ssh`, `docker` (for local builds)

**k3s Cluster Node(s):**
- Linux (Ubuntu 22.04/24.04 tested)
- CPU: 2+ cores
- RAM: 4 GB+ (8 GB recommended when running InfluxDB + Grafana)
- Disk: 20 GB free
- Network: reachable from the control host

---

## Where to Run

Run `deploy.sh` / `one_shot.sh` on **any machine with kubectl access** to your k3s cluster (for example, your Jenkins VM or a laptop that can reach `192.168.56.102`). The scripts expect that your kubeconfig is available (`$KUBECONFIG` or a file path you provide).

---

## Installation

1) **Clone**

```bash
git clone https://github.com/tomeir2105/stockops-cicd.git
cd stockops-cicd
```

2) **Prepare kubeconfig**

- Ensure you have a kubeconfig that can access the cluster (e.g., `k3s-jenkins.yaml`) and either:
  - export it via `export KUBECONFIG=/path/to/k3s-jenkins.yaml`, **or**
  - pass it inside the scripts if they accept a flag/path.

3) **Configure environment**

- Create a local `.env` (not committed) or export variables in your shell (see below).

4) **(Optional) Build & push images locally**

```bash
# Example only – your app repos may live elsewhere
docker build -t meir25/stockops-fetcher:latest ./path/to/fetcher
docker push meir25/stockops-fetcher:latest

docker build -t meir25/stockops-news:latest ./path/to/news
docker push meir25/stockops-news:latest
```

5) **Run deployment**

```bash
# Fast path: apply current manifests
./deploy.sh

# Or full reset + deploy
./one_shot.sh
```

---

## Environment Variables

At minimum, set:

```bash
# Docker Hub (for private pulls or scripted pushes)
export DOCKERHUB_USER="meir25"
export DOCKERHUB_PAT="<dockerhub_access_token>"

# k3s access (if your scripts need SSH for helper steps)
export K3S_HOST="user@192.168.56.102"      # adjust to your host
export K3S_SUDO_PASS="<sudo_password>"     # only if used by your scripts

# Cluster basics
export K3S_IP="192.168.56.102"
export NAMESPACE="ci"

# Kubeconfig
export KUBECONFIG="/path/to/k3s-jenkins.yaml"
```

**Service secrets (examples):**
```bash
# Grafana
export GRAFANA_ADMIN_USER="admin"
export GRAFANA_ADMIN_PASSWORD="changeme"

# InfluxDB
export INFLUXDB_ADMIN_USER="influxadmin"
export INFLUXDB_ADMIN_PASSWORD="changeme"
export INFLUXDB_ORG="stockops"
export INFLUXDB_BUCKET="stocks"
export INFLUXDB_RETENTION="30d"
```

> Secrets are typically injected via templates under `stages/03-k8s-deploy/`. **Do not commit real secrets.**

---

## Usage

**Deploy (or re-deploy) everything:**
```bash
./deploy.sh
```

**Full refresh (clean namespace, re-apply everything):**
```bash
./one_shot.sh
```

**Check cluster state:**
```bash
kubectl -n ci get pods -o wide
kubectl -n ci get svc
kubectl -n ci get deploy,sts,ds,jobs -o wide
```

**View logs:**
```bash
kubectl -n ci logs deploy/stockops-fetcher
kubectl -n ci logs deploy/stockops-news
kubectl -n ci logs deploy/influxdb
kubectl -n ci logs deploy/grafana
```

**Update app image tag (example):**
```bash
# If manifests use an image tag variable, update and re-apply.
kubectl -n ci set image deploy/stockops-fetcher stockops-fetcher=meir25/stockops-fetcher:latest
kubectl -n ci rollout status deploy/stockops-fetcher
```

---

## Accessing Services

- **Grafana** (NodePort):  
  `http://<K3S_IP>:32000` → for example: `http://192.168.56.102:32000`  
  Credentials come from your Grafana secret/template.

- **InfluxDB**: internal Service (default `:8086`) for the fetcher/news deployments.

---

## Troubleshooting

- **ImagePullBackOff** → ensure images exist and are public (or use a pull secret). Verify the tags your manifests reference (`latest` vs a pinned tag).
- **Pods Pending** → increase k3s VM CPU/RAM or free resources.
- **Grafana not reachable** → confirm NodePort `32000` is open and you’re using the right `K3S_IP`.
- **kubectl errors** → confirm kubeconfig path and that your context points to the k3s cluster.

---

## Notes

- This repo focuses on **direct `kubectl apply`** deployment and scripts.  
- Keep `.env`, kubeconfigs, and secret values **out of Git**.  
- Dashboards and datasources are configured via ConfigMaps/Secret templates under `stages/03-k8s-deploy/`.
