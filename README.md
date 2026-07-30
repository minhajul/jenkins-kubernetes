# NestJS + Kubernetes CI/CD with Jenkins

A local DevOps handbook for running NestJS microservices on Kubernetes with a automated Jenkins CI/CD pipeline.

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

# Verify the app health
curl http://localhost:30009/health
```

---

## 🛠️ Essential Makefile Commands

| Command            | Description                                                    |
|:-------------------|:---------------------------------------------------------------|
| `make install`     | First-time setup: builds Jenkins image & applies K8s manifests |
| `make password`    | Prints initial Jenkins admin password                          |
| `make pf`          | Port-forwards Jenkins UI to `http://localhost:8080`            |
| `make deploy-app`  | Builds NestJS app image & deploys to Kubernetes                |
| `make app-status`  | Shows running pods and services for NestJS app                 |
| `make app-logs`    | Tails NestJS app logs                                          |
| `make restart-app` | Performs rolling restart of NestJS app                         |
| `make cleanall`    | Wipes all project-created K8s resources                        |

---

## 📚 Detailed Documentation

For full step-by-step CI/CD pipeline setup, credential configuration, and auto-deploy webhook guides, see
**[docs/cicd-setup.md](docs/cicd-setup.md)**.
