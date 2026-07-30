# PUKU.md

This file provides guidance to puku-cli when working with code in this repository.

## Workflow

Push to `main` → Jenkins detects the push (via `githubPush()` trigger in `Jenkinsfile`) → pipeline builds Docker image → `kubectl set image` rolls out the new deployment. There is no PR review step in this setup; commits on `main` go straight to the cluster.

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

| Target | What it does |
|---|---|
| `make install` | First-time setup: builds `jenkins-custom:lts` + applies Jenkins manifests |
| `make status` | Pods + services + PVCs in `devops-tools` |
| `make app-status` | Status of the NestJS app only |
| `make logs` / `make app-logs` | Tail Jenkins / NestJS logs |
| `make password` | Print initial admin password (waits for pod Ready) |
| `make restart-app` | Rolling restart of the NestJS deployment |
| `make cleanall` | Wipe everything tied to this project (asks for `yes` confirmation) |

## K8s / Jenkins gotchas (learned the hard way — read before editing)

- **Jenkins container runs as root** (`securityContext.runAsUser: 0` in `k8s/jenkins/deployment.yaml`). This is so it can write to the host's Docker socket. Local-dev only — do not copy this to a prod cluster.
- **The `jenkins-admin` ClusterRole must grant `apiGroups: ["*"]`**, not just `[""]`. The core API group alone (`apiGroups: [""]`) doesn't cover `apps/v1` Deployments, so `kubectl set image deployment/...` will be forbidden.
- **The Jenkins job must have `<lightweight>false</lightweight>`** in `config.xml`, or the git checkout stage fails with `fatal: not in a git directory`. Lightweight checkout can't satisfy `GitSCMFileSystem` reliably.
- **NodePort 32000 = Jenkins, 30009 = NestJS app**. Don't change them without updating `Makefile` and docs.
- **The app image is built against the host Docker daemon** (mounted via `/var/run/docker.sock`) and stored on the host — not in a registry. Survives pod restarts because the daemon is on your Mac, but won't survive `make cleanall`.

## File layout

- `app/` — NestJS source. Build/test all happen here.
- `k8s/jenkins/` — Jenkins manifests (Deployment, Service, ServiceAccount, PVC).
- `k8s/app/` — NestJS app manifests.
- `Jenkinsfile` — pipeline definition; path is `Jenkinsfile` at repo root (not `app/Jenkinsfile`).
- `jenkins.Dockerfile` — extends `jenkins/jenkins:lts` with Node 20, Docker CLI, kubectl.
- `Makefile` — all `kubectl` shortcuts.
- `docs/cicd-setup.md` — manual Jenkins setup walkthrough.