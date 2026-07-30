# NestJS + Kubernetes CI/CD with Jenkins & Observability

A local DevOps handbook for running NestJS microservices on Kubernetes with an automated Jenkins CI/CD pipeline and full Grafana + Prometheus + Loki observability.

---

## ⚡ Quick Start (Local Setup)

### 1. Prerequisites
Ensure you have the following installed:
- [Docker Desktop](https://www.docker.com/) / [OrbStack](https://orbstack.dev/) / [Minikube](https://minikube.sigs.k8s.io/)
- `kubectl` CLI
- `make`

### 2. Start Jenkins in Kubernetes
Run the setup command to create the `devops-tools` namespace, build the custom Jenkins image, and deploy Jenkins:

```bash
make install
```

### 3. Get Jenkins Password & Access UI
```bash
# Get the admin password
make password

# Access Jenkins via NodePort at http://localhost:32000
# OR port-forward to http://localhost:8080
make pf
```

### 4. Build & Deploy NestJS App
```bash
# Build the Docker image & deploy to Kubernetes
make deploy-app

# Verify the app health & metrics
curl http://localhost:30009/health
curl http://localhost:30009/metrics
```

### 5. Deploy Monitoring Stack (Grafana + Prometheus + Loki)
```bash
# Apply Grafana, Prometheus, Loki & Promtail manifests
make monitoring-apply

# Access Grafana Dashboard at http://localhost:30030 (or port-forward: make grafana-pf)
# Default Login: Anonymous / admin (pre-provisioned dashboard automatically loaded)
```

---

## 📊 Observability Stack Architecture

- **Prometheus** (`:30090` / `:9090`): Scrapes app metrics from NestJS `/metrics` endpoint.
- **Loki** (`:30100` / `:3100`): Stores pod logs using local filesystem storage.
- **Promtail**: Collects pod/container logs from Kubernetes node and forwards to Loki.
- **Grafana** (`:30030` / `:3000`): Pre-provisioned with Prometheus & Loki datasources and an automated Observability Dashboard.

---

## 🛠️ Essential Makefile Commands

| Command | Description |
| :--- | :--- |
| `make install` | First-time setup: builds Jenkins image & applies K8s manifests |
| `make password` | Prints initial Jenkins admin password |
| `make pf` | Port-forwards Jenkins UI to `http://localhost:8080` |
| `make deploy-app` | Builds NestJS app image & deploys to Kubernetes |
| `make app-status` | Shows running pods and services for NestJS app |
| `make app-logs` | Tails NestJS app logs |
| `make monitoring-apply` | Deploys Grafana, Prometheus, Loki, and Promtail |
| `make monitoring-status` | Checks status of monitoring pods |
| `make grafana-pf` | Port-forwards Grafana UI to `http://localhost:3000` |
| `make cleanall` | Wipes all project-created K8s resources |

---

## 📚 Detailed Documentation

- **[docs/cicd-setup.md](docs/cicd-setup.md)**: Full step-by-step CI/CD pipeline and auto-deploy setup guide.
- **[k8s/monitoring](k8s/monitoring)**: Manifest files for Prometheus, Loki, Promtail, and Grafana.
