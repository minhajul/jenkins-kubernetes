# NestJS + Kubernetes CI/CD with Jenkins & Observability

A local DevOps handbook for running NestJS microservices on Kubernetes with an automated Jenkins CI/CD pipeline and full
Grafana + Prometheus + Loki observability.

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

# Access the UIs via port-forward (services are ClusterIP-only)
make grafana-pf      # http://localhost:3000
make prometheus-pf   # http://localhost:9090
# Grafana: anonymous read-only access; admin login uses the credentials in the
# grafana-admin-credentials Secret (default admin/admin).
```

---

## 📊 Observability Stack Architecture

- **Prometheus**: Scrapes app metrics from NestJS `/metrics` endpoint. Access via `make prometheus-pf` →
  `http://localhost:9090`.
- **Loki**: Stores pod logs using local filesystem storage (persistent PVC).
- **Promtail**: Collects pod/container logs from Kubernetes node and forwards to Loki.
- **Grafana**: Pre-provisioned with Prometheus & Loki datasources and an automated Observability Dashboard. Access via
  `make grafana-pf` → `http://localhost:3000`.

> Monitoring services are `ClusterIP` only (not exposed on NodePorts) — use the `make *-pf` port-forwards to reach them.

---

## 🛠️ Essential Makefile Commands

| Command                  | Description                                                     |
|:-------------------------|:----------------------------------------------------------------|
| `make help`              | Lists all available Makefile targets                            |
| `make info`              | Shows project config (namespace, images, manifest dirs)         |
| `make validate`          | Dry-run validate all manifests (requires a running cluster)     |
| `make install`           | First-time setup: builds Jenkins image & applies K8s manifests  |
| `make password`          | Prints initial Jenkins admin password                           |
| `make pf`                | Port-forwards Jenkins UI to `http://localhost:8080`             |
| `make deploy-app`        | Builds NestJS app image & deploys to Kubernetes                 |
| `make status`            | Shows all pods, services & PVCs in the `devops-tools` namespace |
| `make app-status`        | Shows running pods and services for NestJS app                  |
| `make app-logs`          | Tails NestJS app logs                                           |
| `make monitoring-apply`  | Deploys Grafana, Prometheus, Loki, and Promtail                 |
| `make monitoring-status` | Checks status of monitoring pods                                |
| `make monitoring-logs`   | Tails monitoring pod logs                                       |
| `make grafana-pf`        | Port-forwards Grafana UI to `http://localhost:3000`             |
| `make prometheus-pf`     | Port-forwards Prometheus to `http://localhost:9090`             |
| `make loki-pf`           | Port-forwards Loki to `http://localhost:3100`                   |
| `make prometheus-reload` | Recompute Prometheus config checksum & re-apply                 |
| `make clean`             | Wipes all project-created K8s resources & Docker images         |

---

## 📚 Detailed Documentation

- **[docs/cicd-setup.md](docs/cicd-setup.md)**: Full step-by-step CI/CD pipeline and auto-deploy setup guide.
- **[k8s/monitoring](k8s/monitoring)**: Manifest files for Prometheus, Loki, Promtail, and Grafana.
