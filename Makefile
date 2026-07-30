# Makefile for Jenkins, NestJS App, and Observability on Kubernetes
NS          := devops-tools
JENKINS_DIR := k8s/jenkins
APP_DIR     := k8s/app
MON_DIR     := k8s/monitoring
KUBECTL     := kubectl

.PHONY: help
help: ## Show available Makefile targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---------- 🚀 Setup & Deployments ----------

.PHONY: ns
ns: ## Create namespace
	@$(KUBECTL) create namespace $(NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -

.PHONY: install
install: ns build-jenkins apply-jenkins ## First-time setup: build Jenkins & deploy to K8s

.PHONY: apply-jenkins apply
apply-jenkins apply: ns ## Apply Jenkins manifests
	$(KUBECTL) apply -f $(JENKINS_DIR)/

.PHONY: apply-app
apply-app: ns ## Apply NestJS app manifests
	$(KUBECTL) apply -f $(APP_DIR)/

.PHONY: build-app
build-app: ## Build NestJS Docker image locally
	cd app && docker build -t nestjs-k8s-app:latest .

.PHONY: build-jenkins
build-jenkins: ## Build custom Jenkins Docker image
	docker build -f jenkins.Dockerfile -t jenkins-custom:lts .

.PHONY: deploy-app
deploy-app: build-app apply-app ## Build image & deploy NestJS app to K8s

.PHONY: monitoring-apply apply-monitoring
monitoring-apply apply-monitoring: ns ## Deploy Grafana, Prometheus, Loki, Promtail
	$(KUBECTL) apply -f $(MON_DIR)/

# ---------- 🔍 Status & Logs ----------

.PHONY: status
status: ## Show status of all resources in devops-tools namespace
	$(KUBECTL) get pods,svc,pvc -n $(NS)

.PHONY: app-status status-app
app-status status-app: ## Show status of NestJS app
	$(KUBECTL) get pods,svc -n $(NS) -l app=nestjs-app

.PHONY: app-logs logs-app
app-logs logs-app: ## Tail NestJS app logs
	$(KUBECTL) logs -n $(NS) -l app=nestjs-app -f

.PHONY: logs
logs: ## Tail Jenkins logs
	$(KUBECTL) logs -n $(NS) -l app=jenkins-server -f

.PHONY: monitoring-status status-monitoring
monitoring-status status-monitoring: ## Show status of monitoring stack
	$(KUBECTL) get pods,svc -n $(NS) -l 'app in (prometheus-server,loki,promtail,grafana)'

.PHONY: restart-app
restart-app: ## Restart NestJS app deployment
	$(KUBECTL) rollout restart deploy/nestjs-app -n $(NS)

# ---------- 🔑 Access & Port-Forwards ----------

.PHONY: password
password: ## Print initial Jenkins admin password
	@echo "Fetching Jenkins admin password..."
	@$(KUBECTL) wait --for=condition=ready pod -l app=jenkins-server -n $(NS) --timeout=120s
	@$(KUBECTL) exec -n $(NS) deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword

.PHONY: pf pf-jenkins
pf pf-jenkins: ## Port-forward Jenkins to localhost:8080
	$(KUBECTL) port-forward -n $(NS) svc/jenkins-service 8080:8080

.PHONY: grafana-pf pf-grafana
grafana-pf pf-grafana: ## Port-forward Grafana to localhost:3000
	$(KUBECTL) port-forward -n $(NS) svc/grafana-service 3000:3000

# ---------- 🧹 Teardown ----------

.PHONY: monitoring-delete clean-monitoring
monitoring-delete clean-monitoring: ## Delete monitoring stack
	-$(KUBECTL) delete -f $(MON_DIR)/

.PHONY: clean
clean: ## Teardown all project resources & namespace
	-$(KUBECTL) delete namespace $(NS)
