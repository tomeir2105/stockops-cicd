# StockOps CI/CD on k3s

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  
[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-blue)](https://k3s.io/)  
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-meir25-blue)](https://hub.docker.com)  

---

## Table of Contents

- [Overview](#overview)  
- [Architecture](#architecture)  
- [Components](#components)  
- [Repository Structure](#repository-structure)  
- [Prerequisites](#prerequisites)  
- [Minimum Requirements](#minimum-requirements)  
- [Installation](#installation)  
- [Environment Variables](#environment-variables)  
- [Usage](#usage)  
- [Accessing Services](#accessing-services)  
- [Development Workflow](#development-workflow)  
- [Troubleshooting](#troubleshooting)  
- [Tips & Notes](#tips--notes)  
- [License](#license)  
- [Author](#author)  

---

## Overview

**StockOps CI/CD** is a DevOps practice project for deploying and managing stock monitoring services on a local Kubernetes cluster powered by **k3s**.  

The project demonstrates how to:  
- Build Docker images for services using **Kaniko**  
- Push images to **Docker Hub** automatically  
- Deploy microservices (stock fetcher, news fetcher, InfluxDB, Grafana) to Kubernetes  
- Configure secrets, namespaces, and registry access  
- Expose **Grafana** dashboards externally  

---

## Architecture

```
GitHub (repo: tomeir2105/stockops-cicd)
        │
        ├── one_shot.sh (main entrypoint)
        │
        ▼
Docker Hub (images: meir25/stockops-*)
        │
        ▼
k3s cluster (e.g. VM with IP 192.168.56.102)
  ├── Namespace: ci
  ├── Deployments:
  │     • stockops-fetcher
  │     • stockops-news
  │     • influxdb
  │     • grafana
  └── Services:
        • Grafana exposed on NodePort (default: 32000)
```

---

## Components

| Component   | Description |
|--------------|-------------|
| **k3s cluster** | Lightweight Kubernetes, used here on a VM. |
| **StockOps Fetcher** | Fetches stock prices from external APIs. |
| **StockOps News** | Collects related company news. |
| **InfluxDB** | Time-series database storing stock data. |
| **Grafana** | Visualization dashboards for stock metrics. |

---

## Repository Structure

```
.
├── Dockerfile                  # Base image template
├── Jenkinsfile                 # For Jenkins integration
├── one_shot.sh                 # Full pipeline orchestration
├── setup_env.sh                # Environment variable helper
├── stabilize-ci.sh             # Cleanup/recovery script
├── sync_images.sh              # Image sync helper
├── stages/                     # Individual stages of deployment
│     ├── 00-bind-k3s-ip-remote
│     ├── 01-namespace-and-registry-secret
│     ├── 02-kaniko-build
│     ├── 02b-kaniko-build-news
│     ├── 03-k8s-deploy
│     └── 03b-expose-grafana
├── env                         # Local env files (gitignored)
└── README.md                   # Documentation
```

---

## Prerequisites

- Linux environment (Ubuntu 22.04+ recommended)  
- k3s installed on a VM or host (tested with k3s v1.33.x)  
- `kubectl` installed and configured  
- Docker Hub account with PAT (Personal Access Token)  
- SSH access to the VM hosting k3s  

---

## Minimum Requirements

- **Host Machine (for running Jenkins or scripts):**  
  - CPU: 2+ cores  
  - RAM: 4 GB+  
  - Disk: 20 GB free  
  - Tools: bash, ssh, kubectl, git  

- **k3s Cluster Node(s):**  
  - CPU: 2+ cores  
  - RAM: 4 GB+ (8 GB recommended if running Grafana + InfluxDB)  
  - Disk: 20 GB free  
  - Network: Accessible via SSH from host  
  - OS: Ubuntu 22.04/24.04 (tested)  

---

## Installation

1. **Clone the repository**  

```bash
git clone https://github.com/tomeir2105/stockops-cicd.git
cd stockops-cicd
```

2. **Configure environment variables**  
Create or edit your `.env` file or export variables manually (see [Environment Variables](#environment-variables)).  

3. **Verify cluster access**  

```bash
kubectl --kubeconfig ./k3s-jenkins.yaml get nodes
```

4. **Run one-shot installer**  

```bash
bash one_shot.sh
```

This will:  
- Reset the `ci` namespace  
- Configure secrets for Docker Hub access  
- Build and push images to Docker Hub  
- Deploy all components (fetcher, news, influxdb, grafana)  
- Expose Grafana at port 32000  

---

## Environment Variables

Required:

```bash
export K3S_HOST="user@192.168.56.102"   # Replace with your k3s host IP
export K3S_SUDO_PASS="yourpassword"     # SSH password for sudo if needed
export DOCKERHUB_PAT="your_dockerhub_pat"
```

Optional (can be templated in secrets):

```bash
export GRAFANA_ADMIN_USER="admin"
export GRAFANA_ADMIN_PASSWORD="changeme"
export INFLUXDB_ADMIN_USER="influxadmin"
export INFLUXDB_ADMIN_PASSWORD="changeme"
```

---

## Usage

Run the deployment:

```bash
bash one_shot.sh
```

Check deployments:

```bash
kubectl -n ci get pods
kubectl -n ci get svc
```

Clean and reset:

```bash
bash stabilize-ci.sh
```

Deploy individual stages (for testing):

```bash
bash stages/02-kaniko-build/run.sh
bash stages/03-k8s-deploy/run.sh
```

---

## Accessing Services

- **Grafana**:  
  URL: `http://<k3s-ip>:32000`  
  Default credentials: as defined in `grafana-secret.tmpl.yaml`  

- **InfluxDB**:  
  Accessible internally in the cluster (port 8086).  
  Credentials from `influxdb-secret.yaml`.  

- **Logs**:  

```bash
kubectl -n ci logs deploy/stockops-fetcher
kubectl -n ci logs deploy/stockops-news
```

---

## Development Workflow

1. Modify service code (fetcher/news).  
2. Commit & push to GitHub.  
3. Run `one_shot.sh` to rebuild + redeploy.  
4. Verify changes in Grafana dashboard.  

---

## Troubleshooting

- **Pods stuck in Pending**: Not enough cluster resources → increase VM RAM/CPU.  
- **ImagePullBackOff**: Check Docker Hub credentials, PAT, or rate limits.  
- **Grafana not accessible**: Ensure NodePort `32000` is open in VM firewall.  
- **kubectl not working**: Verify `k3s-jenkins.yaml` is synced from k3s master.  

---

## Tips & Notes

- Keep `.env` and secrets outside Git to avoid leaks.  
- For repeated runs, use `stabilize-ci.sh` before `one_shot.sh`.  
- Use NodePort 32000 → access Grafana externally.  
- Jenkins pipeline integration can automate running `one_shot.sh` after commits.  

---

## License

This project is provided “as-is” for educational / practice / non-commercial use by Meir.  
(Check `LICENSE` for the full terms.)

---

## Author

Maintained by **Meir**  
GitHub: [tomeir2105](https://github.com/tomeir2105)  
Docker Hub: [meir25](https://hub.docker.com/u/meir25)  

---
