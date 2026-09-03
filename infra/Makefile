TERRAFORM ?= terraform
KUBECTL ?= kubectl
HARVESTER_KUBECONFIG ?= $(HOME)/.kube/us-dc-harvester-cluster.yaml
VM_NAMESPACE ?= solutions-rnd-dpdp-demos
VM_PREFIX ?= dpdp
SSH_USER ?= ubuntu
SSH_KEY ?= $(HOME)/.ssh/id_ed25519_dpdp

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
	@ip="$$($(KUBECTL) --kubeconfig "$(HARVESTER_KUBECONFIG)" --namespace "$(VM_NAMESPACE)" get vmi "$(VM_PREFIX)-is" -o jsonpath='{.status.interfaces[0].ipAddress}')" || exit $$?; \
	[ -n "$$ip" ] || { echo "VM $(VM_PREFIX)-is has not reported an IP address yet." >&2; exit 1; }; \
	printf '%s\n' "$$ip"

db-vm-ip:
	@ip="$$($(KUBECTL) --kubeconfig "$(HARVESTER_KUBECONFIG)" --namespace "$(VM_NAMESPACE)" get vmi "$(VM_PREFIX)-db" -o jsonpath='{.status.interfaces[0].ipAddress}')" || exit $$?; \
	[ -n "$$ip" ] || { echo "VM $(VM_PREFIX)-db has not reported an IP address yet." >&2; exit 1; }; \
	printf '%s\n' "$$ip"

ssh-is:
	@ip="$$($(MAKE) --no-print-directory is-vm-ip)" || exit $$?; \
	ssh -i "$(SSH_KEY)" "$(SSH_USER)@$$ip"

ssh-db:
	@ip="$$($(MAKE) --no-print-directory db-vm-ip)" || exit $$?; \
	ssh -i "$(SSH_KEY)" "$(SSH_USER)@$$ip"

validate:
	$(TERRAFORM) fmt -check
	$(TERRAFORM) validate
