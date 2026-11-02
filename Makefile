#─────────────────────────────────────────────────────────────────────────────
# CloudPulse Makefile: the "secret weapon" that brings up the project with a single command.
# make up             from scratch: kind cluster + build images + deploy      (local)
# make forward        open the application at http://localhost:8080
# make down           delete the namespace |  make destroy   delete the cluster
# make deploy IMAGE_REPO=ghcr.io//cloudpulse IMAGE_TAG= \
# KUBE_CONTEXT=    deploys GHCR images to a real cluster
# Secrets: make secrets writes random values to the .secrets.env file (excluded from git).
# No passwords are hardcoded in this file or in the manifests.
# Required tools: docker, kind, kubectl, openssl, envsubst (gettext), terraform (optional).
#─────────────────────────────────────────────────────────────────────────────

SHELL       := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ── Settings (all can be overridden from the command line: make up LOCAL_PORT=9090) ─────
CLUSTER            ?= cloudpulse
NAMESPACE          ?= cloudpulse
KUBE_CONTEXT       ?= kind-$(CLUSTER)
LOCAL_PORT         ?= 8080
APP_URL            ?= http://localhost:$(LOCAL_PORT)
# manifest : Applied from k8s/configmap-secret.yaml
# terraform: ConfigMap/Secret comes from Terraform (make tf-apply)
CONFIG_SOURCE      ?= manifest
IMAGE_REPO         ?= cloudpulse
# MinIO community images have been removed from Docker Hub/Quay; another S3-compatible image can also be provided.
MINIO_IMAGE        ?= cgr.dev/chainguard/minio:latest
METRICS_SERVER_URL ?= https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
SECRETS_FILE       ?= .secrets.env
TAG_FILE           ?= .image-tag
TF                 ?= terraform
TF_DIR             := terraform

GIT_SHA   := $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
IMAGE_TAG ?= $(shell cat $(TAG_FILE) 2>/dev/null)
IMAGE_APP  = $(IMAGE_REPO)-app:$(IMAGE_TAG)
IMAGE_WEB  = $(IMAGE_REPO)-web:$(IMAGE_TAG)

KUBECTL = kubectl --context $(KUBE_CONTEXT) --namespace $(NAMESPACE)

SECRET_VARS   := APP_KEY DB_ROOT_PASSWORD DB_PASSWORD DB_REPLICATION_PASSWORD REDIS_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD
# The list "$APP_URL$IMAGE_APP ..." is passed to envsubst: only these are populated,
# other ${...} expressions in the manifests (MySQL startup scripts) remain as they are.
ENVSUBST_VARS := $(foreach v,APP_URL IMAGE_APP IMAGE_WEB MINIO_IMAGE $(SECRET_VARS),$$$(v))

ifeq ($(CONFIG_SOURCE),manifest)
DEPLOY_DEPS := guard-image-tag secrets
else ifeq ($(CONFIG_SOURCE),terraform)
DEPLOY_DEPS := guard-image-tag
else
$(error CONFIG_SOURCE must be 'manifest' or 'terraform')
endif

# $(call render,): fills the placeholders and writes to stdout.
define render
set -a; [ -f $(SECRETS_FILE) ] && . ./$(SECRETS_FILE); set +a; \
export APP_URL='$(APP_URL)' IMAGE_APP='$(IMAGE_APP)' IMAGE_WEB='$(IMAGE_WEB)' MINIO_IMAGE='$(MINIO_IMAGE)'; \
envsubst '$(ENVSUBST_VARS)' < $(1)
endef

# Converts .secrets.env values into Terraform variables (TF_VAR_*).
# If GHCR_USERNAME and GHCR_PAT are provided, a GHCR image pull secret is also created.
define tf_env
set -a; . ./$(SECRETS_FILE); set +a; \
export TF_VAR_kube_context='$(KUBE_CONTEXT)' TF_VAR_namespace='$(NAMESPACE)' \
  TF_VAR_app_key="$$APP_KEY" TF_VAR_db_root_password="$$DB_ROOT_PASSWORD" \
  TF_VAR_db_password="$$DB_PASSWORD" TF_VAR_db_replication_password="$$DB_REPLICATION_PASSWORD" \
  TF_VAR_redis_password="$$REDIS_PASSWORD" TF_VAR_minio_root_user="$$MINIO_ROOT_USER" \
  TF_VAR_minio_root_password="$$MINIO_ROOT_PASSWORD"; \
if [ -n "$${GHCR_PAT:-}" ]; then \
  export TF_VAR_create_image_pull_secret=true TF_VAR_ghcr_username="$${GHCR_USERNAME:?set GHCR_USERNAME}" TF_VAR_ghcr_pat="$$GHCR_PAT"; \
fi
endef

.PHONY: help check-tools secrets cluster metrics build load guard-image-tag deploy up up-terraform \
        forward status logs-web logs-worker replica-status hpa-demo hpa-watch restart down destroy clean \
        validate tf-init tf-plan tf-apply tf-destroy

help: ## show this help
	@printf '\nCloudPulse: one-command DevOps demo\n\nUsage: make <target>\n\n'
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-16s %s\n", $$1, $$2}'
	@printf '\nExamples:\n  make up\n  make forward\n  make deploy IMAGE_REPO=ghcr.io/<owner>/cloudpulse IMAGE_TAG=sha-abc1234 KUBE_CONTEXT=<ctx>\n\n'

# ── Preparation ────────────────────────────────────────────────────────────────

check-tools: ## verify the required CLI tools are installed
	@missing=0; \
	for t in docker kind kubectl openssl envsubst; do \
	  command -v "$$t" >/dev/null 2>&1 || { echo "✗ missing tool: $$t"; missing=1; }; \
	done; \
	[ "$$missing" -eq 0 ] && echo "✔ all required tools are installed" || exit 1

secrets: $(SECRETS_FILE) ## generate random local secrets into .secrets.env (only if missing)

$(SECRETS_FILE):
	@echo "→ generating $(SECRETS_FILE) with random values (never commit this file)"
	@umask 077; { \
	  echo "APP_KEY=base64:$$(openssl rand -base64 32)"; \
	  echo "DB_ROOT_PASSWORD=$$(openssl rand -hex 16)"; \
	  echo "DB_PASSWORD=$$(openssl rand -hex 16)"; \
	  echo "DB_REPLICATION_PASSWORD=$$(openssl rand -hex 16)"; \
	  echo "REDIS_PASSWORD=$$(openssl rand -hex 16)"; \
	  echo "MINIO_ROOT_USER=cp$$(openssl rand -hex 6)"; \
	  echo "MINIO_ROOT_PASSWORD=$$(openssl rand -hex 16)"; \
	} > $@

cluster: ## create the local kind cluster (idempotent)
	@if kind get clusters 2>/dev/null | grep -x '$(CLUSTER)' >/dev/null; then \
	  echo "✔ kind cluster '$(CLUSTER)' already exists"; \
	else \
	  kind create cluster --name $(CLUSTER); \
	fi

metrics: ## install metrics-server (the HPA needs it); adds the kind-only TLS flag
	kubectl --context $(KUBE_CONTEXT) apply -f $(METRICS_SERVER_URL)
	@if ! kubectl --context $(KUBE_CONTEXT) -n kube-system get deployment metrics-server \
	      -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -e '--kubelet-insecure-tls' >/dev/null; then \
	  kubectl --context $(KUBE_CONTEXT) -n kube-system patch deployment metrics-server --type=json \
	    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'; \
	fi

# ── Images ─────────────────────────────────────────────────────────────────

build: ## build the app + web images (tag is saved to .image-tag)
	@tag="$${TAG:-$(GIT_SHA)-$$(date +%Y%m%d%H%M%S)}"; \
	echo "$$tag" > $(TAG_FILE); \
	echo "→ building $(IMAGE_REPO)-app:$$tag and $(IMAGE_REPO)-web:$$tag"; \
	docker build --target app --build-arg APP_VERSION="$$tag" --build-arg APP_COMMIT_SHA="$(GIT_SHA)" -t "$(IMAGE_REPO)-app:$$tag" .; \
	docker build --target web -t "$(IMAGE_REPO)-web:$$tag" .

guard-image-tag:
	@test -n "$(IMAGE_TAG)" || { echo "✗ IMAGE_TAG is empty: run 'make build' or pass IMAGE_TAG=<tag>"; exit 1; }

load: guard-image-tag ## load the built images into the kind cluster
	kind load docker-image "$(IMAGE_APP)" "$(IMAGE_WEB)" --name $(CLUSTER)

# ── Deployment ─────────────────────────────────────────────────────────────────

deploy: $(DEPLOY_DEPS) ## apply all manifests in order and wait until everything is ready
	@echo "→ deploying $(IMAGE_APP) and $(IMAGE_WEB) to context '$(KUBE_CONTEXT)', namespace '$(NAMESPACE)' (config: $(CONFIG_SOURCE))"
ifeq ($(CONFIG_SOURCE),manifest)
	kubectl --context $(KUBE_CONTEXT) create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl --context $(KUBE_CONTEXT) apply -f -
	@echo "→ applying ConfigMap + Secret (secrets rendered from $(SECRETS_FILE))"
	@$(call render,k8s/configmap-secret.yaml) | $(KUBECTL) apply -f -
	@if [ -n "$${GHCR_PAT:-}" ]; then \
	  $(KUBECTL) create secret docker-registry ghcr-pull-secret --docker-server=ghcr.io \
	    --docker-username="$${GHCR_USERNAME:?set GHCR_USERNAME}" --docker-password="$$GHCR_PAT" \
	    --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	fi
endif
	@echo "→ applying data layer: MySQL primary + replica, Redis, MinIO"
	@$(call render,k8s/mysql-statefulset.yaml) | $(KUBECTL) apply -f -
	@$(call render,k8s/redis-deployment.yaml) | $(KUBECTL) apply -f -
	@$(call render,k8s/minio-deployment.yaml) | $(KUBECTL) apply -f -
	$(KUBECTL) rollout status statefulset/mysql-primary --timeout=300s
	$(KUBECTL) rollout status statefulset/mysql-replica --timeout=300s
	$(KUBECTL) rollout status deployment/redis --timeout=180s
	$(KUBECTL) rollout status deployment/minio --timeout=180s
	@# Önce migration Job'ı (Job spec'i değiştirilemez; eskisi silinir), bitince web/worker.
	$(KUBECTL) delete job cloudpulse-migrate --ignore-not-found --wait=true
	@echo "→ running database migrations (Job)"
	@$(call render,k8s/laravel-deployment.yaml) | $(KUBECTL) apply -l app.kubernetes.io/component=migrate -f -
	@$(KUBECTL) wait --for=condition=complete job/cloudpulse-migrate --timeout=300s || { \
	  echo "✗ migration failed, last log lines:"; $(KUBECTL) logs job/cloudpulse-migrate --tail=40; exit 1; }
	@echo "→ applying web (nginx + php-fpm), worker, HPA, PDB"
	@$(call render,k8s/laravel-deployment.yaml) | $(KUBECTL) apply -l 'app.kubernetes.io/component!=migrate' -f -
	$(KUBECTL) rollout status deployment/cloudpulse-web --timeout=300s
	$(KUBECTL) rollout status deployment/cloudpulse-worker --timeout=180s

up: check-tools cluster metrics build load deploy ## ONE COMMAND: kind cluster + build + deploy everything
	@echo ""
	@echo "✔ CloudPulse is deployed. Open it with:  make forward   ($(APP_URL))"

up-terraform: check-tools cluster metrics tf-apply build load ## like 'up', but ConfigMap/Secrets come from Terraform
	@$(MAKE) --no-print-directory deploy CONFIG_SOURCE=terraform
	@echo ""
	@echo "✔ CloudPulse is deployed (config via Terraform). Open it with:  make forward   ($(APP_URL))"

# ── Daily Jobs ────────────────────────────────────────────────────────────

forward: ## open the app locally via port-forward (Ctrl+C to stop)
	@echo "CloudPulse → $(APP_URL)"
	$(KUBECTL) port-forward svc/cloudpulse-web $(LOCAL_PORT):80

status: ## show pods, services and the HPA
	$(KUBECTL) get pods,svc,hpa

logs-web: ## follow the web pods' logs (nginx + php-fpm)
	$(KUBECTL) logs -l app.kubernetes.io/name=cloudpulse-web --all-containers --prefix --tail=50 -f

logs-worker: ## follow the queue worker's logs
	$(KUBECTL) logs -l app.kubernetes.io/name=cloudpulse-worker --prefix --tail=50 -f

replica-status: ## show MySQL replication health (IO/SQL threads, lag)
	@$(KUBECTL) exec mysql-replica-0 -- bash -c 'MYSQL_PWD="$$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SHOW REPLICA STATUS\G"' \
	  | grep -E 'Source_Host|Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source|Last_IO_Error:|Last_SQL_Error:'

hpa-demo: ## generate load so the HPA scales the web pods (Ctrl+C to stop)
	$(KUBECTL) run load-generator --rm -i --restart=Never --image=busybox:1.37 -- \
	  /bin/sh -c 'while true; do wget -q -O- http://cloudpulse-web/ > /dev/null; done'

hpa-watch: ## watch the HPA react (run in a second terminal during hpa-demo)
	$(KUBECTL) get hpa cloudpulse-web -w

restart: ## rolling-restart web and worker (e.g. after a ConfigMap change)
	$(KUBECTL) rollout restart deployment/cloudpulse-web deployment/cloudpulse-worker

down: ## delete the namespace (all workloads and volumes)
	kubectl --context $(KUBE_CONTEXT) delete namespace $(NAMESPACE) --ignore-not-found

destroy: ## delete the whole kind cluster
	kind delete cluster --name $(CLUSTER)

clean: ## remove local build state (.image-tag); .secrets.env is kept on purpose
	rm -f $(TAG_FILE)

# ── Validation ───────────────────────────────────────────────────────────────

validate: ## static checks (kubeconform, terraform fmt, hadolint), whichever are installed
	@export APP_URL=http://localhost IMAGE_APP=example/app:ci IMAGE_WEB=example/web:ci MINIO_IMAGE=example/minio:ci $(foreach v,$(SECRET_VARS),$(v)=placeholder); \
	if command -v kubeconform >/dev/null 2>&1; then \
	  for f in k8s/*.yaml; do envsubst '$(ENVSUBST_VARS)' < "$$f" | kubeconform -strict -summary -; done; \
	else echo "- kubeconform not installed, skipping manifest validation"; fi; \
	if command -v $(TF) >/dev/null 2>&1; then \
	  $(TF) -chdir=$(TF_DIR) fmt -check -recursive && echo "✔ $(TF) fmt"; \
	else echo "- $(TF) not installed, skipping terraform fmt"; fi; \
	if command -v hadolint >/dev/null 2>&1; then \
	  hadolint Dockerfile && echo "✔ hadolint"; \
	else echo "- hadolint not installed, skipping Dockerfile lint"; fi

# ── Terraform Path ──────────────────────────────────────────────────────────

tf-init: ## terraform init
	$(TF) -chdir=$(TF_DIR) init

tf-plan: secrets ## terraform plan (secrets are passed as TF_VAR_* from .secrets.env)
	@$(tf_env); $(TF) -chdir=$(TF_DIR) init -input=false >/dev/null && $(TF) -chdir=$(TF_DIR) plan

tf-apply: secrets ## terraform apply: namespace + ConfigMap + Secrets (+ GHCR pull secret)
	@$(tf_env); $(TF) -chdir=$(TF_DIR) init -input=false >/dev/null && $(TF) -chdir=$(TF_DIR) apply

tf-destroy: secrets ## terraform destroy
	@$(tf_env); $(TF) -chdir=$(TF_DIR) destroy
