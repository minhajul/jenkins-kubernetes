# PUKU.md

This file provides guidance to puku-cli when working with code in this repository.

## Workflow

Push to `main` → Jenkins detects the push (via `githubPush()` trigger in `Jenkinsfile`) → pipeline builds Docker image →
`kubectl set image` rolls out the new deployment. There is no PR review step in this setup; commits on `main` go
straight to the cluster.

## Build / test commands

The `app/` package has standard npm scripts. Always work inside `app/`:

```bash
cd app
npm ci            # clean install (use this, not `npm install`)
npm run build     # nest build → dist/
npm test          # placeholder; no real tests yet
npm start         # node dist/main.js (after build)
```

There is no `lint` script — formatting is handled by a Prettier hook (see `.puku-cli/settings.json`).

## Day-to-day Makefile targets

Run `make help` for the full list. The ones you'll touch most:

| Target                        | What it does                                                              |
|-------------------------------|---------------------------------------------------------------------------|
| `make install`                | First-time setup: builds `jenkins-custom:lts` + applies Jenkins manifests |
| `make status`                 | Pods + services + PVCs in `devops-tools`                                  |
| `make app-status`             | Status of the NestJS app only                                             |
| `make logs` / `make app-logs` | Tail Jenkins / NestJS logs                                                |
| `make password`               | Print initial admin password (waits for pod Ready)                        |
| `make restart-app`            | Rolling restart of the NestJS deployment                                  |
| `make validate`               | Dry-run all manifests (no cluster changes)                                |
| `make info`                   | Show namespace, image names, and manifest dirs                            |
| `make clean`                  | Wipe everything tied to this project: namespace + Docker images           |

## K8s / Jenkins gotchas (learned the hard way — read before editing)

- **Jenkins container runs as root** (`securityContext.runAsUser: 0` in `k8s/jenkins/deployment.yaml`). This is so it
  can write to the host's Docker socket. It's hardened as far as the socket requires: `allowPrivilegeEscalation: false`,
  all capabilities dropped, runtime seccomp, read-only socket mount. Local-dev only — see *Moving to production* below.
- **The `jenkins-admin` ClusterRole covers `apps` (deployments/replicasets) plus read-only core resources** —
  it must NOT be narrowed to `apiGroups: [""]` only, or `kubectl set image deployment/...` will be forbidden. It is
  currently least-privilege for the pipeline (`set image` + `rollout status`); extend it if you add pipeline steps.
- **The Jenkins job must have `<lightweight>false</lightweight>`** in `config.xml`, or the git checkout stage fails with
  `fatal: not in a git directory`. Lightweight checkout can't satisfy `GitSCMFileSystem` reliably.
- **NodePort 32000 = Jenkins, 30009 = NestJS app** — these are the only NodePorts. Monitoring services are
  `ClusterIP` only; reach them via `make grafana-pf` / `make prometheus-pf` / `make loki-pf`. Don't change them without
  updating `Makefile` and docs.
- **The app image is built against the host Docker daemon** (mounted via `/var/run/docker.sock`) and stored on the
  host — not in a registry. Survives pod restarts because the daemon is on your Mac, but won't survive `make clean`.

## Moving to production

The host-socket build (root + `/var/run/docker.sock`) only works on a single node where the kubelet and daemon share
state, and images never leave the host. Two migration paths:

### Option A — DinD sidecar (simplest)

Add a privileged `docker:dind` sidecar to the Jenkins pod, point `DOCKER_HOST=tcp://localhost:2375`, drop the host
socket mount, and run the Jenkins container as non-root (`runAsUser: 1000`). Images now live inside the DinD daemon,
so also push to a local registry (e.g. `registry:2` deployment) and point the app Deployment's `imagePullPolicy` at it —
otherwise kubelet can't pull builds produced inside the sidecar.

### Option B — Kaniko / Buildah (most secure, recommended for prod)

Remove Docker entirely from the build step. The pipeline executes a kaniko pod that builds the image from the `app/`
context and pushes it to a registry; Jenkins then runs `kubectl set image`. No privileged containers, no host socket.
Requires: a registry, a `kaniko` step in the `Jenkinsfile` (or a `BuildConfig` if you move to OpenShift), and updated
image refs/pull policy in `k8s/app/deployment.yaml`.

## File layout

- `app/` — NestJS source. Build/test all happen here.
- `k8s/jenkins/` — Jenkins manifests (Deployment, Service, ServiceAccount, PVC).
- `k8s/app/` — NestJS app manifests.
- `Jenkinsfile` — pipeline definition; path is `Jenkinsfile` at repo root (not `app/Jenkinsfile`).
- `jenkins.Dockerfile` — extends `jenkins/jenkins:lts` with Node 20, Docker CLI, kubectl.
- `Makefile` — all `kubectl` shortcuts.
- `docs/cicd-setup.md` — manual Jenkins setup walkthrough.