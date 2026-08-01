# Makefile for Jenkins, NestJS App, and Observability on Kubernetes
SHELL      := /bin/bash
.DEFAULT_GOAL := help

NS          := devops-tools
JENKINS_DIR := k8s/jenkins
APP_DIR     := k8s/app
MON_DIR     := k8s/monitoring
KUBECTL     := kubectl
DOCKER      := docker

IMG_APP     := nestjs-k8s-app:latest
IMG_JENKINS := jenkins-custom:lts

APP_SELECTOR    := app=nestjs-app
JENKINS_SELECTOR := app=jenkins-server
MON_SELECTOR    := app in (prometheus-server,loki,promtail,grafana)

.PHONY: help
help: ## Show available Makefile targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+([[:space:]]+[a-zA-Z_-]+)*:.*?## / {split($$1, a, /[[:space:]]+/); printf "  \033[36m%-20s\033[0m %s\n", a[1], $$2}' $(MAKEFILE_LIST)

# ---------- Info & Validation ----------

.PHONY: info
info: ## Show project config (namespace, images, dirs)
	@printf "Namespace        : %s\n" "$(NS)"
	@printf "Jenkins image    : %s\n" "$(IMG_JENKINS)"
	@printf "App image        : %s\n" "$(IMG_APP)"
	@printf "Jenkins manifests: %s\n" "$(JENKINS_DIR)"
	@printf "App manifests    : %s\n" "$(APP_DIR)"
	@printf "Monitoring       : %s\n" "$(MON_DIR)"

.PHONY: ns-print
ns-print: ## Print just the namespace (for scripts/hooks)
	@printf "%s\n" "$(NS)"

.PHONY: validate dry-run
validate dry-run: ## Dry-run validate all manifests (requires a running cluster)
	@for d in $(JENKINS_DIR) $(APP_DIR) $(MON_DIR); do \
		echo "==> Validating $$d"; \
		$(KUBECTL) apply --dry-run=server -f $$d/ >/dev/null || exit 1; \
	done
	@echo "OK: all manifests valid"

# ---------- Setup & Deployments ----------

.PHONY: ns
ns: ## Create namespace (idempotent)
	@$(KUBECTL) create namespace $(NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -

.PHONY: install
install: ns build-jenkins apply-jenkins ## First-time setup: build Jenkins & deploy to K8s

.PHONY: build-jenkins
build-jenkins: jenkins.Dockerfile ## Build custom Jenkins Docker image
	$(DOCKER) build -f jenkins.Dockerfile -t $(IMG_JENKINS) .

.PHONY: build-app
build-app: app/Dockerfile ## Build NestJS Docker image locally
	cd app && $(DOCKER) build -t $(IMG_APP) .

.PHONY: apply-jenkins
apply-jenkins: ns ## Apply Jenkins manifests
	$(KUBECTL) apply -f $(JENKINS_DIR)/

.PHONY: apply-app
apply-app: ns ## Apply NestJS app manifests
	$(KUBECTL) apply -f $(APP_DIR)/

.PHONY: deploy-app
deploy-app: build-app apply-app ## Build image & deploy NestJS app to K8s

.PHONY: monitoring-apply
monitoring-apply: ns ## Deploy Grafana, Prometheus, Loki, Promtail
	$(KUBECTL) apply -f $(MON_DIR)/

# ---------- Status & Logs ----------

.PHONY: status
status: ## Show status of all resources in the namespace
	$(KUBECTL) get pods,svc,pvc -n $(NS)

.PHONY: app-status
app-status: ## Show status of NestJS app
	$(KUBECTL) get pods,svc -n $(NS) -l $(APP_SELECTOR)

.PHONY: monitoring-status
monitoring-status: ## Show status of monitoring stack
	$(KUBECTL) get pods,svc -n $(NS) -l '$(MON_SELECTOR)'

.PHONY: describe-app
describe-app: ## Describe NestJS app resources
	$(KUBECTL) describe deployment,svc -n $(NS) -l $(APP_SELECTOR)

.PHONY: app-logs
app-logs: ## Tail NestJS app logs
	$(KUBECTL) logs -n $(NS) -l $(APP_SELECTOR) -f

.PHONY: logs
logs: ## Tail Jenkins logs
	$(KUBECTL) logs -n $(NS) -l $(JENKINS_SELECTOR) -f

.PHONY: monitoring-logs
monitoring-logs: ## Tail monitoring pod logs
	$(KUBECTL) logs -n $(NS) -l '$(MON_SELECTOR)' -f

.PHONY: restart-app
restart-app: ## Restart NestJS app deployment
	$(KUBECTL) rollout restart deploy/nestjs-app -n $(NS)

.PHONY: status-app
status-app: app-status

# ---------- Access & Port-Forwards ----------

.PHONY: password
password: ## Print initial Jenkins admin password
	@echo "Fetching Jenkins admin password..."
	@$(KUBECTL) wait --for=condition=ready pod -l $(JENKINS_SELECTOR) -n $(NS) --timeout=120s
	@$(KUBECTL) exec -n $(NS) deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword

.PHONY: pf pf-jenkins
pf pf-jenkins: ## Port-forward Jenkins to localhost:8080
	$(KUBECTL) port-forward -n $(NS) svc/jenkins-service 8080:8080

.PHONY: grafana-pf pf-grafana
grafana-pf pf-grafana: ## Port-forward Grafana to localhost:3000
	$(KUBECTL) port-forward -n $(NS) svc/grafana-service 3000:3000

.PHONY: prometheus-pf pf-prometheus
prometheus-pf pf-prometheus: ## Port-forward Prometheus to localhost:9090
	$(KUBECTL) port-forward -n $(NS) svc/prometheus-service 9090:9090

.PHONY: loki-pf pf-loki
loki-pf pf-loki: ## Port-forward Loki to localhost:3100
	$(KUBECTL) port-forward -n $(NS) svc/loki-service 3100:3100

.PHONY: prometheus-reload
prometheus-reload: ## Recompute prometheus config checksum & apply (rolls out on change)
	@HASH=$$(awk '/^  prometheus\.yml: \|/ {f=1; next} f && /^---/ {f=0} f {sub(/^    /, ""); print}' $(MON_DIR)/prometheus.yaml | shasum -a 256 | cut -d' ' -f1); \
	sed -i.bak "s|checksum/config: [0-9a-f]*|checksum/config: $$HASH|" $(MON_DIR)/prometheus.yaml; \
	rm -f $(MON_DIR)/prometheus.yaml.bak; \
	$(KUBECTL) apply -f $(MON_DIR)/prometheus.yaml

# ---------- Teardown ----------

.PHONY: monitoring-delete
monitoring-delete: ## Delete monitoring stack
	$(KUBECTL) delete -f $(MON_DIR)/ || true

.PHONY: clean
clean: ## Complete teardown: namespace, PVCs & project Docker images
	@echo "==> [1/2] Deleting Kubernetes namespace '$(NS)' & all resources..."
	@$(KUBECTL) delete namespace $(NS) || true
	@echo "==> [2/2] Removing built project Docker images..."
	@$(DOCKER) rmi -f $(IMG_APP) $(IMG_JENKINS) 2>/dev/null || true
	@echo "Cleanup complete!"

# ---------- Aliases (keep CLI ergonomics) ----------

.PHONY: apply
apply: apply-jenkins ## Alias: apply Jenkins manifests

.PHONY: clean-monitoring
clean-monitoring: monitoring-delete ## Alias: delete monitoring stack

.PHONY: apply-monitoring
apply-monitoring: monitoring-apply ## Alias: deploy monitoring stack

.PHONY: logs-app
logs-app: app-logs ## Alias: tail NestJS app logs

.PHONY: status-monitoring
status-monitoring: monitoring-status ## Alias: show monitoring stack status

.PHONY: app
app: app-status ## Alias: show NestJS app status

.PHONY: mon
mon: monitoring-status ## Alias: show monitoring stack status
