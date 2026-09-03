TERRAFORM ?= terraform
SSH_USER ?= ubuntu
SSH_KEY ?= $(HOME)/.ssh/id_ed25519

.PHONY: help init plan apply ips is-vm-ip db-vm-ip ssh-is ssh-db validate

help:
	@echo "Targets: init, plan, apply, ips, is-vm-ip, db-vm-ip, ssh-is, ssh-db, validate"

init:
	$(TERRAFORM) init

plan:
	$(TERRAFORM) plan

apply:
	$(TERRAFORM) apply

ips:
	$(TERRAFORM) output vms

is-vm-ip:
	@$(TERRAFORM) output -raw is_vm_ip

db-vm-ip:
	@$(TERRAFORM) output -raw db_vm_ip

ssh-is:
	ssh -i "$(SSH_KEY)" "$(SSH_USER)@$$($(TERRAFORM) output -raw is_vm_ip)"

ssh-db:
	ssh -i "$(SSH_KEY)" "$(SSH_USER)@$$($(TERRAFORM) output -raw db_vm_ip)"

validate:
	$(TERRAFORM) fmt -check
	$(TERRAFORM) validate
