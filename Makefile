ACCESS_DIR := infra/access
VMS_DIR := infra/vms
KUBECONFIG_PATH := $(CURDIR)/kube-config/harvester.yaml
SSH_USER ?= ubuntu
SSH_KEY ?= $(HOME)/.ssh/id_ed25519

.PHONY: help access-init access-plan access-apply vms-init vms-plan vms-apply ips ssh-is ssh-db validate

help:
	@echo "Targets:"
	@echo "  access-plan    plan the namespace-scoped Harvester credential"
	@echo "  access-apply   create the credential and write kube-config/harvester.yaml"
	@echo "  vms-plan       plan the IS and MySQL VMs"
	@echo "  vms-apply      create the IS and MySQL VMs after reviewing the plan"
	@echo "  ips            print the VM addresses returned by Harvester"
	@echo "  ssh-is         open an SSH session on the Identity Server VM"
	@echo "  ssh-db         open an SSH session on the MySQL VM"
	@echo "  validate       format-check and validate both Terraform roots"

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
	terraform -chdir=$(VMS_DIR) plan

vms-apply: vms-init
	terraform -chdir=$(VMS_DIR) apply

ips:
	@terraform -chdir=$(VMS_DIR) output vms

ssh-is:
	ssh -i $(SSH_KEY) $(SSH_USER)@$$(terraform -chdir=$(VMS_DIR) output -raw is_vm_ip)

ssh-db:
	ssh -i $(SSH_KEY) $(SSH_USER)@$$(terraform -chdir=$(VMS_DIR) output -raw db_vm_ip)

validate:
	terraform fmt -check -recursive infra
	terraform -chdir=$(ACCESS_DIR) validate
	terraform -chdir=$(VMS_DIR) validate
