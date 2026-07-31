# CI/CD Setup Guide: NestJS on Kubernetes with Jenkins

This guide details how to set up an automated CI/CD pipeline that builds, tests, packages, and deploys a NestJS
application to Kubernetes using Jenkins.

---

## 1. Architecture Overview

```
┌──────────┐    git push    ┌──────────────┐   docker build   ┌──────────────┐
│ Developer │ ───────────►  │   Jenkins    │ ───────────────► │ Local / Hub  │
└──────────┘                │  (this repo) │                  │ Docker Image │
                            └──────┬───────┘                  └──────┬───────┘
                                   │ kubectl set image               │
                                   ▼                                  ▼
                            ┌──────────────────────────────────────────┐
                            │  Kubernetes cluster (devops-tools ns)   │
                            │  Deployment: nestjs-app                 │
                            └──────────────────────────────────────────┘
```

**Execution Steps:**

1. Developer pushes code to GitHub.
2. Jenkins pipeline is triggered automatically (Webhook or Polling).
3. Jenkins runs `npm ci`, compiles TypeScript, and runs test suites.
4. Jenkins builds a Docker image tagged `nestjs-k8s-app:build-<BUILD_NUMBER>`.
5. Jenkins executes `kubectl set image` for zero-downtime rolling deployment.

---

## 2. Prerequisites

Verify requirements before proceeding:

- Kubernetes Cluster (`devops-tools` namespace created via `make ns`).
- Jenkins running inside K8s (`make install`).
- Local NestJS app dependencies checked (`cd app && npm ci`).

---

## 3. Jenkins & Cluster Access Configuration

Jenkins needs access to manage Kubernetes deployments:

### Copy Host Kubeconfig to Jenkins Pod

Run the following command to allow `kubectl` inside Jenkins to interact with your cluster:

```bash
POD_NAME=$(kubectl get pods -n devops-tools -l app=jenkins-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n devops-tools $POD_NAME -- mkdir -p /root/.kube
kubectl cp ~/.kube/config devops-tools/$POD_NAME:/root/.kube/config
```

---

## 4. Pipeline Job Creation

1. Go to **Jenkins Dashboard** → **New Item**.
2. Enter Name: `nestjs-k8s-app-pipeline` → Select **Pipeline** → Click **OK**.
3. Under **Pipeline Configuration**:
    - **Definition**: Pipeline script from SCM
    - **SCM**: Git
    - **Repository URL**: `<your-github-repo-url>`
    - **Branch**: `*/main` or `*/master`
    - **Script Path**: `Jenkinsfile`
4. Click **Save**.

---

## 5. Enable Automatic Deploy on Git Push

### Option A: GitHub Webhook (Recommended for Public Jenkins)

1. In your GitHub repo: **Settings** → **Webhooks** → **Add webhook**.
2. **Payload URL**: `http://<YOUR_JENKINS_URL>/github-webhook/`
3. **Content type**: `application/json`
4. Select **Just the push event** → Click **Add webhook**.
5. In Jenkins Pipeline config: Check **GitHub hook trigger for GITScm polling**.

### Option B: Local Webhook via `ngrok` (For Local Dev)

If Jenkins is running on `localhost`:

```bash
# Expose NodePort 32000 or HTTP 8080
ngrok http 32000
```

Use the generated ngrok URL in GitHub Webhook Settings:
`https://<ngrok-id>.ngrok-free.app/github-webhook/`

### Option C: SCM Polling (Fallback)

If webhooks cannot be reached, update `Jenkinsfile` to poll GitHub periodically:

```groovy
triggers {
    pollSCM('*/5 * * * *') // Check every 5 minutes
}
```

---

## 6. Verification & Useful Commands

| Task                    | Command                                                      |
|:------------------------|:-------------------------------------------------------------|
| **Check App Pods**      | `make app-status`                                            |
| **Tail App Logs**       | `make app-logs`                                              |
| **Verify App Endpoint** | `curl http://localhost:30009/health`                         |
| **Rollback Deployment** | `kubectl -n devops-tools rollout undo deployment/nestjs-app` |
| **Tail Jenkins Logs**   | `make logs`                                                  |
| **Check Monitoring**    | `make monitoring-status` / `make monitoring-logs`            |
| **Validate Manifests**  | `make validate` (needs a running cluster)                    |
| **Show Project Config** | `make info`                                                  |

---

## 7. Common Issues & Quick Fixes

| Problem                             | Cause                              | Solution                                                 |
|:------------------------------------|:-----------------------------------|:---------------------------------------------------------|
| `kubectl: command not found`        | Missing `kubectl` in Jenkins image | Ensure `make build-jenkins` was run during install       |
| `Unauthorized / Connection Refused` | `kubeconfig` missing in Jenkins    | Re-run `kubectl cp ~/.kube/config ...` command           |
| `ImagePullBackOff`                  | App Docker image not found         | Run `make build-app` locally or configure registry login |
| Webhook not triggering build        | Missing trailing slash in URL      | Ensure webhook URL ends with `/github-webhook/`          |
