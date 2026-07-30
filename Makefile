# Makefile for Jenkins on Kubernetes
# Usage: make <target>

NS             := devops-tools
APP            := jenkins
JENKINS_DIR    := k8s/jenkins
APP_K8S_DIR    := k8s/app
KUBECTL        := kubectl

# ---------- Setup ----------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: ns
ns: ## Create the devops-tools namespace
	$(KUBECTL) create namespace $(NS) || true

.PHONY: install
install: ns apply ## First-time install: create namespace + apply all Jenkins manifests

.PHONY: apply
apply: ## Apply all Jenkins manifests (volume, serviceAccount, service, deployment)
	$(KUBECTL) apply -f $(JENKINS_DIR)/volume.yaml
	$(KUBECTL) apply -f $(JENKINS_DIR)/serviceAccount.yaml
	$(KUBECTL) apply -f $(JENKINS_DIR)/service.yaml
	$(KUBECTL) apply -f $(JENKINS_DIR)/deployment.yaml

.PHONY: apply-app
apply-app: ## Apply NestJS app manifests (in k8s/app/)
	$(KUBECTL) apply -f $(APP_K8S_DIR)/serviceAccount.yaml
	$(KUBECTL) apply -f $(APP_K8S_DIR)/service.yaml
	$(KUBECTL) apply -f $(APP_K8S_DIR)/deployment.yaml

.PHONY: build-app
build-app: ## Build the NestJS app Docker image locally
	cd app && docker build -t nestjs-k8s-app:latest .

.PHONY: deploy-app
deploy-app: build-app apply-app ## Build image and deploy app to K8s

.PHONY: restart-app
restart-app: ## Rolling restart of the NestJS deployment
	$(KUBECTL) rollout restart deploy/nestjs-app -n $(NS)

.PHONY: app-status
app-status: ## Status of the NestJS app
	$(KUBECTL) get all -n $(NS) -l app=nestjs-app

.PHONY: app-logs
app-logs: ## Tail NestJS app logs
	$(KUBECTL) logs -n $(NS) -l app=nestjs-app -f

# ---------- Status ----------

.PHONY: status
status: ## Show overall status (pods, svc, pvc)
	@echo "==> Pods"
	@$(KUBECTL) get pods -n $(NS) -o wide
	@echo
	@echo "==> Services"
	@$(KUBECTL) get svc -n $(NS)
	@echo
	@echo "==> PVCs"
	@$(KUBECTL) get pvc -n $(NS)

.PHONY: pods
pods: ## List pods
	$(KUBECTL) get pods -n $(NS)

.PHONY: logs
logs: ## Tail jenkins logs
	$(KUBECTL) logs -n $(NS) -f deploy/$(APP)

.PHONY: describe
describe: ## Describe the jenkins pod (for debugging)
	$(KUBECTL) describe deploy/$(APP) -n $(NS)

.PHONY: events
events: ## Show recent events in namespace
	$(KUBECTL) get events -n $(NS) --sort-by=.lastTimestamp

# ---------- Access ----------

.PHONY: url
url: ## Show how to reach Jenkins
	@echo "NodePort: http://$$($(KUBECTL) get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):32000"
	@echo "Port-forward: make pf   (then http://localhost:8080)"

.PHONY: pf
pf: ## Port-forward jenkins to localhost:8080
	$(KUBECTL) port-forward -n $(NS) svc/$(APP)-service 8080:8080

.PHONY: shell
shell: ## Open a shell inside the jenkins container
	$(KUBECTL) exec -n $(NS) -it deploy/$(APP) -- bash

.PHONY: password
password: ## Print the initial admin password
	@$(KUBECTL) exec -n $(NS) deploy/$(APP) -- cat /var/jenkins_home/secrets/initialAdminPassword

# ---------- Lifecycle ----------

.PHONY: restart
restart: ## Restart the jenkins deployment
	$(KUBECTL) rollout restart deploy/$(APP) -n $(NS)

.PHONY: scale
scale: ## Scale replicas (usage: make scale n=2)
	$(KUBECTL) scale deploy/$(APP) -n $(NS) --replicas=$(n)

.PHONY: undo
undo: ## Rollback to previous deployment
	$(KUBECTL) rollout undo deploy/$(APP) -n $(NS)

# ---------- Teardown ----------

.PHONY: delete
delete: ## Delete all Jenkins manifests (keeps namespace)
	-$(KUBECTL) delete -f $(JENKINS_DIR)/deployment.yaml
	-$(KUBECTL) delete -f $(JENKINS_DIR)/service.yaml
	-$(KUBECTL) delete -f $(JENKINS_DIR)/serviceAccount.yaml
	-$(KUBECTL) delete -f $(JENKINS_DIR)/volume.yaml

.PHONY: delete-app
delete-app: ## Delete NestJS app manifests (keeps namespace)
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/deployment.yaml
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/service.yaml
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/serviceAccount.yaml

.PHONY: purge
purge: ## Delete everything including namespace
	-$(KUBECTL) delete namespace $(NS)

.PHONY: reset
reset: delete apply ## Delete and re-apply (fresh state, keeps namespace)

.PHONY: cleanall
cleanall: ## NUCLEAR: wipe everything related to THIS project only
	@echo "=========================================="
	@echo "  WARNING: This will wipe this project"
	@echo "=========================================="
	@echo "About to:"
	@echo "  - Delete manifests: deployment, service, serviceAccount, volume"
	@echo "  - Delete namespace '$(NS)' and all its resources"
	@echo "  - Delete any PVs claimed by the '$(NS)' namespace"
	@echo "  - Remove the 'local-storage' StorageClass (project-specific)"
	@echo "  - Remove the 'jenkins/jenkins:lts' Docker image"
	@echo "  - Kill any stuck port-forwards on 8080/32000"
	@echo "  - Remove local .jenkins/ or jenkins_home/ dirs in this repo"
	@echo
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	@echo
	@echo "==> [1/7] Deleting manifests..."
	-$(KUBECTL) delete -f $(JENKINS_DIR)/deployment.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(JENKINS_DIR)/service.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(JENKINS_DIR)/serviceAccount.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(JENKINS_DIR)/volume.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/deployment.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/service.yaml --ignore-not-found
	-$(KUBECTL) delete -f $(APP_K8S_DIR)/serviceAccount.yaml --ignore-not-found
	@echo
	@echo "==> [2/7] Deleting namespace '$(NS)'..."
	-$(KUBECTL) delete namespace $(NS) --ignore-not-found
	-$(KUBECTL) wait --for=delete namespace/$(NS) --timeout=60s 2>/dev/null || true
	@echo
	@echo "==> [3/7] Deleting PVs that were bound to '$(NS)'..."
	-$(KUBECTL) get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="$(NS)")]}{.metadata.name}{"\n"}{end}' | \
		while read pv; do \
			[ -n "$$pv" ] && $(KUBECTL) delete pv $$pv --ignore-not-found 2>/dev/null || true; \
		done
	@echo
	@echo "==> [4/7] Deleting project-specific StorageClass..."
	-$(KUBECTL) delete storageclass local-storage --ignore-not-found
	@echo
	@echo "==> [5/7] Removing the jenkins Docker image..."
	-docker rmi -f jenkins/jenkins:lts 2>/dev/null || true
	@echo
	@echo "==> [6/7] Killing stuck port-forwards on 8080/32000..."
	-lsof -ti:8080 2>/dev/null | xargs -r kill -9 2>/dev/null || true
	-lsof -ti:32000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
	@echo
	@echo "==> [7/7] Cleaning local jenkins dirs in this repo..."
	@find . -maxdepth 5 -type d \( -name '.jenkins' -o -name 'jenkins_home' -o -name 'jenkins-data' \) -exec rm -rf {} + 2>/dev/null || true
	@echo
	@echo "=========================================="
	@echo "  Project state cleaned. Other apps untouched."
	@echo "=========================================="
