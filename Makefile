ACCESS_DIR := infra/access
VMS_DIR := infra/vms
KUBECONFIG_PATH := $(CURDIR)/kube-config/harvester.yaml
SECRET_VARS := $(if $(wildcard $(VMS_DIR)/secret.tfvars),-var-file=secret.tfvars,)

.PHONY: help access-init access-plan access-apply vms-init vms-plan vms-apply ips ssh-is ssh-db setup validate

help:
	@echo "Targets:"
	@echo "  access-plan    plan the namespace-scoped Harvester credential"
	@echo "  access-apply   create the credential and write kube-config/harvester.yaml"
	@echo "  vms-plan       plan the IS and MySQL VMs"
	@echo "  vms-apply      create the IS and MySQL VMs after reviewing the plan"
	@echo "  ips            print the VM addresses returned by Harvester"
	@echo "  ssh-is         open an SSH session on the Identity Server VM"
	@echo "  ssh-db         open an SSH session on the MySQL VM"
	@echo "  setup          install MySQL, WSO2 IS, and the built accelerator"
	@echo "  validate       format-check Terraform and lint deployment scripts"

access-init:
	terraform -chdir=$(ACCESS_DIR) init

access-plan: access-init
	terraform -chdir=$(ACCESS_DIR) plan

access-apply: access-init
	terraform -chdir=$(ACCESS_DIR) apply
	@mkdir -p $(dir $(KUBECONFIG_PATH))
	@umask 077; terraform -chdir=$(ACCESS_DIR) output -raw kubeconfig > $(KUBECONFIG_PATH)
	@echo "Wrote $(KUBECONFIG_PATH) with mode 0600"

vms-init:
	terraform -chdir=$(VMS_DIR) init

vms-plan: vms-init
	terraform -chdir=$(VMS_DIR) plan $(SECRET_VARS)

vms-apply: vms-init
	terraform -chdir=$(VMS_DIR) apply $(SECRET_VARS)

ips:
	@terraform -chdir=$(VMS_DIR) output vms

ssh-is:
	./scripts/ssh.sh is

ssh-db:
	./scripts/ssh.sh db

setup:
	./scripts/setup-all.sh

validate:
	terraform fmt -check -recursive infra
	shellcheck -x -P scripts scripts/*.sh scripts/remote/*.sh
	python3 -m py_compile scripts/remote/patch-datasources.py
