# AKS -> ACR/MAR Chaos Studio game-day orchestrator.
# Repeatable loop:  make cycle   (up -> chaos -> prep)   then   make run EXP=...   then   make reset
#
# Override any variable, e.g.:  make up RG=rg-demo LOCATION=westus2 PREFIX=demo ENABLE_CMK=true
SHELL := /bin/bash

RG         ?= rg-acr-chaos
LOCATION   ?= eastus
PREFIX     ?= acrchaos
ENABLE_CMK ?= false
NAMESPACE  ?= chaos-pullers
HOLD_MIN   ?= 10
EXP        ?= $(PREFIX)-a1-nsg-block-acr
# Node SKU/zones must be offered + have quota in your sub/region (see: az vm list-skus).
AKS_VM_SIZE ?= Standard_D2s_v3
AKS_ZONES   ?= []
# ACR replica regions (JSON array). Fewer = faster/cheaper live runs; use AZ-capable regions.
REPLICAS   ?= ["westus3"]

export RG LOCATION PREFIX ENABLE_CMK NAMESPACE

.DEFAULT_GOAL := help
.PHONY: help lint whatif up chaos prep run collect preflight down purge reset cycle experiments

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-11s\033[0m %s\n",$$1,$$2}'
	@echo ""
	@echo "  Vars: RG=$(RG) LOCATION=$(LOCATION) PREFIX=$(PREFIX) ENABLE_CMK=$(ENABLE_CMK) EXP=$(EXP)"

lint: ## Compile both Bicep templates (offline, no Azure needed)
	az bicep build --file infra/main.bicep --stdout > /dev/null
	az bicep build --file infra/chaos.bicep --stdout > /dev/null
	@echo "bicep OK"

whatif: ## Preview infra changes against Azure (RG must exist)
	az deployment group what-if -g $(RG) -f infra/main.bicep \
	  -p namePrefix=$(PREFIX) location=$(LOCATION) enableCmk=$(ENABLE_CMK) aksVmSize=$(AKS_VM_SIZE) aksZones='$(AKS_ZONES)' replicaRegions='$(REPLICAS)'

up: lint ## Create the RG + deploy infra (writes .chaos.env)
	az group create -n $(RG) -l $(LOCATION) -o none
	az deployment group create -g $(RG) -n main -f infra/main.bicep \
	  -p namePrefix=$(PREFIX) location=$(LOCATION) enableCmk=$(ENABLE_CMK) aksVmSize=$(AKS_VM_SIZE) aksZones='$(AKS_ZONES)' replicaRegions='$(REPLICAS)' -o none
	az deployment group show -g $(RG) -n main --query properties.outputs -o json > .deploy-outputs.json
	@jq -r '"export ACR_NAME=\(.acrName.value)","export ACR_LOGIN=\(.acrLoginServer.value)","export AKS_NAME=\(.aksName.value)","export NSG_NAME=\(.nsgName.value)","export LAW_ID=\(.logAnalyticsId.value)","export KV_NAME=\(if (.keyVaultId.value|length)>0 then (.keyVaultId.value|split("/")|last) else "" end)"' .deploy-outputs.json > .chaos.env
	@echo "wrote .chaos.env:"; cat .chaos.env

chaos: ## Deploy Chaos targets + experiments (needs .chaos.env)
	@set -a; . ./.chaos.env; set +a; \
	EXTRA=""; if [ "$(ENABLE_CMK)" = "true" ]; then EXTRA="-p enableKeyVaultExperiment=true keyVaultName=$$KV_NAME"; fi; \
	az deployment group create -g $(RG) -n chaos -f infra/chaos.bicep \
	  -p namePrefix=$(PREFIX) nsgName=$$NSG_NAME aksName=$$AKS_NAME acrLoginServer=$$ACR_LOGIN $$EXTRA -o none; \
	echo "experiments deployed"

prep: ## Install Chaos Mesh, seed the registry, render + apply workloads
	@set -a; . ./.chaos.env; set +a; \
	RESOURCE_GROUP=$(RG) AKS_NAME=$$AKS_NAME bash scripts/10-setup-chaos-mesh.sh; \
	ACR_NAME=$$ACR_NAME NAMESPACE=$(NAMESPACE) bash scripts/40-prep-registry.sh; \
	REGISTRY=$$ACR_LOGIN NAMESPACE=$(NAMESPACE) bash scripts/45-render-workloads.sh

run: ## Run one experiment: probe -> start EXP -> hold -> cancel -> collect -> record
	@set -a; . ./.chaos.env; set +a; \
	SUB=$$(az account show --query id -o tsv); \
	BASE="https://management.azure.com/subscriptions/$$SUB/resourceGroups/$(RG)/providers/Microsoft.Chaos/experiments/$(EXP)"; \
	RUN_DIR="results/$(EXP)-$$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$$RUN_DIR"; \
	RESOURCE_GROUP=$(RG) AKS_NAME=$$AKS_NAME ACR_NAME=$$ACR_NAME bash scripts/probe-reachability.sh 2>&1 | tee "$$RUN_DIR/probe-before.txt" || true; \
	echo ">> starting $(EXP)"; az rest --method post --url "$$BASE/start?api-version=2024-01-01"; \
	echo ">> holding $(HOLD_MIN)m"; sleep $$(( $(HOLD_MIN) * 60 )); \
	RESOURCE_GROUP=$(RG) AKS_NAME=$$AKS_NAME ACR_NAME=$$ACR_NAME bash scripts/probe-reachability.sh 2>&1 | tee "$$RUN_DIR/probe-during.txt" || true; \
	az rest --method post --url "$$BASE/cancel?api-version=2024-01-01" || true; \
	OUT_DIR="$$RUN_DIR" LAW_ID=$$LAW_ID bash scripts/collect-results.sh || true; \
	EXP=$(EXP) RUN_DIR="$$RUN_DIR" HOLD_MIN=$(HOLD_MIN) bash scripts/record-run.sh; \
	echo ">> run recorded in $$RUN_DIR/summary.md"

collect: ## Re-run the SLI queries and save results/
	@set -a; . ./.chaos.env; set +a; LAW_ID=$$LAW_ID bash scripts/collect-results.sh

preflight: ## Check readiness to run experiments
	@RG=$(RG) bash scripts/preflight.sh

experiments: ## List deployed experiments
	az resource list -g $(RG) --resource-type Microsoft.Chaos/experiments --query "[].name" -o tsv

down: ## Delete the RG (async, fast) — leaves any CMK vault soft-deleted
	az group delete -n $(RG) --yes --no-wait
	@rm -f .chaos.env .deploy-outputs.json

purge: ## Purge a soft-deleted CMK vault (needed to reuse the name)
	@RG=$(RG) LOCATION=$(LOCATION) bash scripts/50-teardown.sh

reset: ## Full teardown: delete RG (sync) + purge CMK vault + clean local state
	@RG=$(RG) LOCATION=$(LOCATION) bash scripts/50-teardown.sh

cycle: up chaos prep ## Full stand-up ready to run experiments (no teardown)
	@echo ">> Ready. Run:  make run EXP=$(EXP)   then   make reset"
