TERRAFORM ?= terraform
VIRTCTL ?= virtctl
HARVESTER_KUBECONFIG ?= $(HOME)/.kube/us-dc-harvester-cluster.yaml
VM_NAMESPACE ?= solutions-rnd-dpdp-demos
VM_PREFIX ?= dpdp

.PHONY: help init plan apply console-is console-db validate

help:
	@echo "Targets: init, plan, apply, console-is, console-db, validate"

init:
	$(TERRAFORM) init

plan:
	$(TERRAFORM) plan

apply:
	$(TERRAFORM) apply

console-is:
	KUBECONFIG="$(HARVESTER_KUBECONFIG)" $(VIRTCTL) console "$(VM_PREFIX)-is" --namespace "$(VM_NAMESPACE)"

console-db:
	KUBECONFIG="$(HARVESTER_KUBECONFIG)" $(VIRTCTL) console "$(VM_PREFIX)-db" --namespace "$(VM_NAMESPACE)"

validate:
	$(TERRAFORM) fmt -check
	$(TERRAFORM) validate
