# StockOps CI/CD on k3s

## 📌 Overview
This repository contains the **StockOps CI/CD pipeline**, designed and tested to run on a **local [k3s](https://k3s.io/) Kubernetes cluster**.  
It provides a one-shot deployment flow that:  
- Cleans and resets the target namespace  
- Builds container images using **Kaniko** and pushes them to Docker Hub  
- Deploys the **fetcher**, **news service**, **InfluxDB**, and **Grafana**  
- Exposes Grafana via NodePort for external access  

The system is meant for local experimentation, education, and DevOps practice — lightweight enough for VirtualBox/VM setups, but still close to production-grade workflows.

---

## 🚀 Architecture

```
GitHub (repo: tomeir2105/stockops-cicd)
        │
        ├── one_shot.sh (main entrypoint)
        │
        ▼
Docker Hub (images: meir25/stockops-*)
        │
        ▼
k3s cluster (192.168.56.102)
  ├── Namespace: ci
  ├── Deployments:
  │     • stockops-fetcher
  │     • stockops-news
  │     • influxdb
  │     • grafana
  └── Services:
        • Grafana exposed at NodePort 32000
```

---

## ⚙️ Components

- **k3s cluster**: Lightweight Kubernetes running on `192.168.56.102`
- **Fetcher**: Python-based service fetching stock data
- **News**: Service fetching related stock news
- **InfluxDB**: Time-series database for storing stock prices
- **Grafana**: Visualization dashboard exposed on NodePort

---

## 📂 Repository Structure

```
.
├── Dockerfile              # Base Dockerfile
├── Jenkinsfile             # Jenkins pipeline definition
├── one_shot.sh             # Main script to build and deploy everything
├── stabilize-ci.sh         # Utility script for stabilizing namespace
├── stages/                 # CI/CD stages (Kaniko build, deploy, expose Grafana, etc.)
│   ├── 00-bind-k3s-ip-remote
│   ├── 01-namespace-and-registry-secret
│   ├── 02-kaniko-build
│   ├── 02b-kaniko-build-news
│   ├── 03-k8s-deploy
│   └── 03b-expose-grafana
└── README.md               # Project documentation
```

---

## ▶️ Usage

### 1. Prerequisites
- A running **k3s cluster** on `192.168.56.102`
- Access from a CI/CD host (`192.168.56.101`)
- Docker Hub account (`meir25`)
- GitHub repo access (`tomeir2105/stockops-cicd`)
- `kubectl` configured with the cluster kubeconfig

### 2. Environment Variables
Set these before running:
```bash
export K3S_HOST="user@192.168.56.102"
export K3S_SUDO_PASS="user"
export DOCKERHUB_PAT="your-dockerhub-token"
```

### 3. Run deployment
```bash
bash one_shot.sh
```

The script will:
1. Ensure k3s API is bound on 192.168.56.102
2. Fetch kubeconfig
3. Clean and recreate `ci` namespace
4. Create Docker Hub secrets
5. Run Kaniko builds for fetcher and news
6. Deploy fetcher, news, InfluxDB, Grafana
7. Expose Grafana at `http://192.168.56.102:32000`

---

## 🌐 Access Grafana
Open your browser at:
```
http://192.168.56.102:32000
```
Default credentials are defined in `stages/03-k8s-deploy/grafana-secret.tmpl.yaml`.

---

## 🔑 Notes
- This is a **k3s-specific project** (tested on Ubuntu 24.04 VM with k3s v1.33.x).
- Avoid committing secrets (`.env`, `k3s-jenkins.yaml`) — they are ignored by `.gitignore`.
- `stages/` folder scripts are modular; `one_shot.sh` orchestrates them in the right order.

---

## 🛠️ Development Workflow
- Update code/services
- Push changes to GitHub
- Run `one_shot.sh` → new Docker images are built & pushed → k3s redeploys updated pods automatically

---

## 📜 License
This project is maintained by **Meir** and intended for learning, testing, and DevOps practice with k3s.

