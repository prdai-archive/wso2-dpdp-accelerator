TERRAFORM ?= terraform
KUBECTL ?= kubectl
VIRTCTL_INSTALL_DIR ?= $(HOME)/.local/bin
VIRTCTL ?= $(VIRTCTL_INSTALL_DIR)/virtctl
HARVESTER_KUBECONFIG ?= $(HOME)/.kube/us-dc-harvester-cluster.yaml
VM_NAMESPACE ?= solutions-rnd-dpdp-demos
VM_PREFIX ?= dpdp
SSH_USER ?= ubuntu
SSH_KEY ?= $(HOME)/.ssh/id_ed25519_dpdp

.PHONY: help init plan apply install-virtctl ips is-vm-ip db-vm-ip ssh-is ssh-db console-is console-db validate

help:
	@echo "Targets: init, plan, apply, install-virtctl, ips, is-vm-ip, db-vm-ip, ssh-is, ssh-db, console-is, console-db, validate"

init:
	$(TERRAFORM) init

plan:
	$(TERRAFORM) plan

apply:
	$(TERRAFORM) apply

install-virtctl:
	@version="$$(curl -fsSL https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)"; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	curl -fL "https://github.com/kubevirt/kubevirt/releases/download/$$version/virtctl-$$version-linux-amd64" -o "$$tmp"; \
	install -d "$(VIRTCTL_INSTALL_DIR)"; \
	install -m 0755 "$$tmp" "$(VIRTCTL_INSTALL_DIR)/virtctl"; \
	"$(VIRTCTL_INSTALL_DIR)/virtctl" version

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

console-is:
	KUBECONFIG="$(HARVESTER_KUBECONFIG)" $(VIRTCTL) console "$(VM_PREFIX)-is" --namespace "$(VM_NAMESPACE)"

console-db:
	KUBECONFIG="$(HARVESTER_KUBECONFIG)" $(VIRTCTL) console "$(VM_PREFIX)-db" --namespace "$(VM_NAMESPACE)"

validate:
	$(TERRAFORM) fmt -check
	$(TERRAFORM) validate
