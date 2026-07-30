# CI/CD Setup for NestJS on Kubernetes with Jenkins

This document walks you through setting up a complete CI/CD pipeline that builds the NestJS app, packages it into a
Docker image, and deploys it to your Kubernetes cluster using Jenkins.

---

## 1. Architecture Overview

```
┌──────────┐    git push    ┌──────────────┐   docker build   ┌──────────────┐
│ Developer │ ───────────►  │   Jenkins    │ ───────────────► │  Docker Hub  │
└──────────┘                │  (this repo) │                  │  / registry  │
                            └──────┬───────┘                  └──────┬───────┘
                                   │ kubectl set image              │
                                   ▼                                 ▼
                            ┌──────────────────────────────────────────┐
                            │  Kubernetes cluster (devops-tools ns)   │
                            │  Deployment: nestjs-app                 │
                            └──────────────────────────────────────────┘
```

**Flow:**

1. Developer pushes code to Git.
2. Jenkins pipeline is triggered (webhook or polling).
3. Jenkins installs deps, builds TypeScript, runs tests.
4. Jenkins builds a Docker image tagged `nestjs-k8s-app:build-<n>`.
5. Jenkins runs `kubectl set image` to roll out the new image.
6. Kubernetes performs a rolling update — zero downtime.

---

## 2. Prerequisites

You should already have these from earlier in this repo:

| Component                                         | How to verify                       |
|---------------------------------------------------|-------------------------------------|
| Jenkins running in K8s (`devops-tools` namespace) | `kubectl get pods -n devops-tools`  |
| `kubectl` CLI available inside Jenkins container  | `kubectl version --client`          |
| `docker` CLI inside Jenkins container             | `docker version`                    |
| `kubeconfig` mounted into Jenkins                 | see Section 3                       |
| NestJS app builds locally                         | `cd app && npm ci && npm run build` |

---

## 3. Configure Jenkins to Talk to Your Cluster

Jenkins needs to run `kubectl` and `docker` against **your host cluster**. By default, the Jenkins Pod can only reach
in-cluster resources — for a single-node cluster, we want it to talk to the same cluster it's running on.

### Option A: In-cluster config (recommended for production)

Mount the service account token into the Jenkins pod. Jenkins already has the SA we created (`jenkins-admin`), so:

```bash
# Copy the SA token into a Secret the Jenkins pod can mount
kubectl -n devops-tools create secret generic jenkins-kubeconfig \
  --from-file=config=/Users/minhajul/.kube/config

# Edit Jenkins deployment to mount it (see deployment.yaml in this repo)
```

### Option B: Mount host kubeconfig (simpler for local dev)

If your Jenkins is running **on OrbStack/docker-desktop** and you want to reach the host cluster:

```bash
# Get the in-cluster kubeconfig
kubectl get secret $(kubectl -n devops-tools get sa jenkins-admin -o jsonpath='{.secrets[0].name}') \
  -n devops-tools -o jsonpath='{.data.token}' | base64 -d

# OR copy ~/.kube/config from your host into the Jenkins pod
kubectl cp ~/.kube/config devops-tools/<jenkins-pod>:/root/.kube/config
```

Easier approach — just exec into Jenkins and copy the kubeconfig:

```bash
kubectl exec -n devops-tools -it <jenkins-pod> -- bash
# Inside the pod:
mkdir -p ~/.kube
# (paste your kubeconfig here)
```

---

## 4. Create the Jenkins Pipeline Job

### 4.1 Add Docker Hub (or your registry) credentials

1. Jenkins → **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**
2. Kind: **Username with password**
3. ID: `docker-hub-creds`
4. Username/password: your Docker Hub account

### 4.2 Add Git credentials (if repo is private)

1. Same screen → **Add Credentials**
2. Kind: **Username with password** (or SSH key)
3. ID: `github-creds`

### 4.3 Create the Pipeline

1. Jenkins Dashboard → **New Item**
2. Name: `nestjs-k8s-app-pipeline`
3. Type: **Pipeline** → OK
4. Under **Pipeline**:
    - Definition: **Pipeline script from SCM**
    - SCM: **Git**
    - Repository URL: `<your git repo>`
    - Credentials: select `github-creds`
    - Branch: `*/main` (or `*/master`)
    - Script Path: `Jenkinsfile`  ← **note: root of repo, not `app/`**
5. Save.

### 4.4 Set Up Automatic Deployment on Git Push

To trigger builds and deployments automatically when pushing to GitHub, you need to configure the connection between GitHub and Jenkins.

#### Option A: Webhook-based Trigger (Recommended for Public Jenkins)
If your Jenkins instance is publicly accessible on the internet:

1. **Configure GitHub Webhook:**
   - Go to your GitHub Repository → **Settings** → **Webhooks** → **Add webhook**.
   - **Payload URL:** `http://<YOUR_PUBLIC_JENKINS_URL>/github-webhook/` (Make sure to include the trailing slash `/`).
   - **Content type:** `application/json`
   - **Which events?** Choose **Just the push event**.
   - Click **Add webhook**.
2. **Configure Jenkins Job:**
   - In your Jenkins job configuration, scroll down to the **Build Triggers** section.
   - Check the box for **GitHub hook trigger for GITScm polling**.
   - Save the configuration.
3. **Pipeline Configuration:**
   - The `Jenkinsfile` contains the `githubPush()` trigger in the `triggers` block, which registers the job for webhook triggers:
     ```groovy
     triggers {
         githubPush()
     }
     ```

#### Option B: Webhook-based Trigger via ngrok (Recommended for Local Dev)
If your Jenkins is running locally (e.g. inside Kubernetes via Docker Desktop / OrbStack at `localhost` / `NodePort`), GitHub cannot send webhooks directly to a private IP. Use `ngrok` or `localtunnel` to create a public URL:

1. **Expose Jenkins port 8080 (or your NodePort) via ngrok:**
   ```bash
   ngrok http 8080
   # OR if exposing via NodePort 32000
   ngrok http 32000
   ```
2. **Get the Public URL:**
   - `ngrok` will provide a public forwarding address (e.g., `https://xxxx-xx-xx-xx.ngrok-free.app`).
3. **Configure GitHub Webhook:**
   - Use the ngrok URL as the base URL: `https://xxxx-xx-xx-xx.ngrok-free.app/github-webhook/`.
4. Ensure **GitHub hook trigger for GITScm polling** is enabled in your Jenkins job.

#### Option C: Polling SCM (Fallback if webhooks/tunnels are not possible)
If you cannot use webhooks, you can configure Jenkins to check (poll) GitHub for changes periodically:

1. **Update the `Jenkinsfile` `triggers` block:**
   Replace the `githubPush()` trigger with `pollSCM(...)`:
   ```groovy
   triggers {
       pollSCM('*/5 * * * *') // Check for changes every 5 minutes
   }
   ```
   *Note: SCM polling can cause delay and puts extra load on GitHub APIs, so webhooks are always preferred.*

---

## 5. Push the Code

```bash
cd /Users/minhajul/Code/DevOps/tektonlabs/jenkins-kubernetes
git init
git add .
git commit -m "Initial NestJS + K8s setup"
git remote add origin <your-repo-url>
git push -u origin main
```

Then in Jenkins: **Build Now**.

---

## 6. What Happens During a Build

| Stage        | Command                                    | Result                                    |
|--------------|--------------------------------------------|-------------------------------------------|
| Checkout     | `git clone`                                | Source code in workspace                  |
| Install      | `cd app && npm ci`                         | `node_modules/` populated                 |
| Build        | `cd app && npm run build`                  | `app/dist/` with compiled JS              |
| Test         | `cd app && npm test`                       | Test results                              |
| Build Docker | `docker build -t nestjs-k8s-app:build-N .` | Image in local Docker daemon              |
| Deploy       | `kubectl set image ...`                    | Rolling update of `nestjs-app` deployment |

---

## 7. Verify the Deployment

```bash
# From your host machine
kubectl get pods -n devops-tools -l app=nestjs-app

# Wait for the new pods to be Running
kubectl rollout status deployment/nestjs-app -n devops-tools

# Hit the app
curl http://localhost:30009
# → "Hello from NestJS on Kubernetes!"

curl http://localhost:30009/health
# → {"status":"ok","uptime":12.34}
```

Or use the Makefile added in this repo (see Section 7.1):

```bash
make app-status     # status of the NestJS deployment only
make app-logs       # tail app logs
```

### 7.1 Two sets of Kubernetes manifests — what's the difference?

This repo contains **two distinct sets of K8s manifests**, and it's important not to mix them up:

| Location                                                                          | Deploys                               | Stateful?                                               | Image                    |
|-----------------------------------------------------------------------------------|---------------------------------------|---------------------------------------------------------|--------------------------|
| **`k8s/jenkins/`** (`volume.yaml`, `serviceAccount.yaml`, `service.yaml`, `deployment.yaml`) | **Jenkins** — the CI/CD runner itself | Yes — needs the `jenkins-pv-claim` PVC to persist state | `jenkins/jenkins:lts`    |
| **`k8s/app/`** (`deployment.yaml`, `service.yaml`, `serviceAccount.yaml`)         | **Your NestJS application**           | No — stateless, scales horizontally                     | `nestjs-k8s-app:build-N` |

They live in the same `devops-tools` namespace but are otherwise completely independent:

- You can delete Jenkins without affecting the app (assuming the app's image exists somewhere).
- You can scale/redeploy the app without restarting Jenkins.

### 7.2 Useful Makefile targets

The `Makefile` distinguishes the two clearly. Common targets:

**Jenkins (CI tool) — `k8s/jenkins/` manifests:**

```bash
make install         # create ns + apply all Jenkins manifests
make apply           # apply Jenkins manifests only
make status          # overall cluster status
make logs            # tail Jenkins logs
make pf              # port-forward Jenkins to localhost:8080
make password        # print initial admin password
make cleanall        # wipe everything (see Makefile for details)
```

**NestJS app — `k8s/app/` manifests:**

```bash
make build-app       # build the Docker image locally
make apply-app       # apply only the app's K8s manifests
make deploy-app      # build image + apply manifests (one shot)
make app-status      # pods/svc for the NestJS app
make app-logs        # tail NestJS app logs
make restart-app     # rolling restart
make delete-app      # remove the app (keeps namespace)
```

If you forget which is which, just run `make help` — it lists everything.

---

## 8. Push Images to a Remote Registry (Optional)

The default `Jenkinsfile` uses local images only — fine for single-node clusters. For multi-node or production:

1. **Login in Jenkinsfile** — add a `Login to Registry` stage:

```groovy
stage('Login to Registry') {
  steps {
    withCredentials([usernamePassword(
      credentialsId: 'docker-hub-creds',
      usernameVariable: 'USER',
      passwordVariable: 'PASS'
    )]) {
      sh 'echo $PASS | docker login -u $USER --password-stdin'
    }
  }
}
```

2. **Tag with your registry** in `environment`:

```groovy
IMAGE_NAME = 'your-dockerhub-user/nestjs-k8s-app'
```

3. **Push** in `Deploy` stage:

```groovy
sh "docker push ${IMAGE_NAME}:${BUILD_TAG}"
```

4. **Set `imagePullPolicy: Always`** in `k8s/app/deployment.yaml`.

---

## 9. Rollback

If a deploy breaks something:

```bash
# From CLI
kubectl -n devops-tools rollout undo deployment/nestjs-app

# From Jenkins — add a "Rollback" stage or job parameter
```

---

## 10. Add Tests (Recommended Next Step)

Replace the placeholder `npm test` with something real:

```bash
cd app
npm install --save-dev jest @nestjs/testing supertest
```

Then create `app/test/app.e2e-spec.ts` and update `package.json`:

```json
"scripts": {
  "test": "jest"
}
```

The Jenkinsfile's `Test` stage will pick it up automatically.

---

## 11. Common Issues

| Symptom                                           | Cause                                                   | Fix                                                        |
|---------------------------------------------------|---------------------------------------------------------|------------------------------------------------------------|
| `kubectl: command not found`                      | Jenkins pod doesn't have kubectl                        | Install or mount in via init container                     |
| `ImagePullBackOff` (Jenkins)                      | Registry auth missing for `jenkins/jenkins:lts`         | Use `imagePullPolicy: IfNotPresent` or pre-pull the image  |
| `ImagePullBackOff` (NestJS app)                   | App image not built/pushed; registry auth missing       | Run `make build-app` locally first, then `make deploy-app` |
| Pod stays `Pending`                               | Cluster can't satisfy PVC/node-affinity                 | Check `kubectl describe pod`                               |
| New image not picked up                           | Same image tag reused                                   | Use unique tags (we use `build-${BUILD_NUMBER}`)           |
| Jenkinsfile path not found                        | Wrong `Script Path`                                     | Set to `Jenkinsfile` (repo root)                           |
| `make apply-app` fails with "namespace not found" | Namespace wasn't created                                | Run `make ns` first, or `make install` to do everything    |
| App 404s at `localhost:30009`                     | Wrong NodePort or app pod not Ready                     | `kubectl get pods -n devops-tools -l app=nestjs-app`       |
| NestJS pod restarts in a loop                     | App fails health check; check `/health` endpoint exists | It does — verify with `make app-logs`                      |
| `cleanall` aborted                                | Did not type `yes` exactly                              | Run again and type `yes` (lowercase, no spaces)            |

---

## 12. File Layout Summary

```
jenkins-kubernetes/
├── app/                          # NestJS source
│   ├── src/
│   │   ├── main.ts
│   │   ├── app.module.ts
│   │   ├── app.controller.ts
│   │   └── app.service.ts
│   ├── package.json
│   ├── package-lock.json
│   ├── tsconfig.json
│   ├── nest-cli.json
│   ├── Dockerfile                # multi-stage, prod-only deps, non-root
│   ├── .dockerignore
│   └── .gitignore
├── k8s/
│   ├── jenkins/                  # K8s manifests for Jenkins (the CI tool)
│   │   ├── deployment.yaml
│   │   ├── service.yaml          # NodePort 32000
│   │   ├── serviceAccount.yaml   # SA + ClusterRole + ClusterRoleBinding
│   │   └── volume.yaml           # jenkins-pv-claim (PVC)
│   └── app/                      # K8s manifests for the NestJS app
│       ├── deployment.yaml       # 2 replicas, probes on /health
│       ├── service.yaml          # NodePort 30009
│       └── serviceAccount.yaml
├── Jenkinsfile                   # CI/CD pipeline (Checkout → Deploy)
├── docs/
│   └── cicd-setup.md             # This document
└── Makefile                      # Day-to-day kubectl shortcuts (Jenkins + app)
```

---

Happy shipping! 🚀
