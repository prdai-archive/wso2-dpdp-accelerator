# Data-center infrastructure

Terraform provisions two Ubuntu 24.04 VMs on Harvester with the
[`wso2/open-cloud-datacenter`](https://github.com/wso2/open-cloud-datacenter)
modules pinned to `terraform/v0.1.7`.

| VM | Intended role | vCPU | RAM | Root disk |
| --- | --- | ---: | ---: | ---: |
| `<prefix>-is` | Identity Server | 6 | 12 GiB | 50 GiB |
| `<prefix>-db` | Database | 2 | 4 GiB | 50 GiB |

The split stays within the quoted total of 8 vCPU, 16 GiB RAM, and 100 GiB
storage. This PR only provisions infrastructure and SSH access. It does not
install or configure WSO2 Identity Server, a database, or the accelerator.

## Prerequisites

- Terraform 1.7 or newer
- a Harvester bootstrap kubeconfig that can create namespace access
- the Harvester API address, tenant namespace, Ubuntu image, and VM network
- one SSH public key for every person who needs VM access

## Create namespace-scoped access

The bootstrap kubeconfig is used only by `infra/access`. The resulting
service-account kubeconfig is written to the git-ignored
`kube-config/harvester.yaml` with mode 0600.

```bash
cp infra/access/terraform.tfvars.example infra/access/terraform.tfvars
# Fill in every REPLACE value.
terraform -chdir=infra/access init
terraform -chdir=infra/access plan
# Review the plan before applying it.
terraform -chdir=infra/access apply
mkdir -p kube-config
umask 077
terraform -chdir=infra/access output -raw kubeconfig > kube-config/harvester.yaml
```

## Provision the VMs

Copy the variables file and add each collaborator's public key to
`ssh_authorized_keys`. Keys should be collected through an authenticated channel;
private keys must never be shared.

```bash
cp infra/vms/terraform.tfvars.example infra/vms/terraform.tfvars
# Fill in the tenant values and SSH public keys.
terraform -chdir=infra/vms init
terraform -chdir=infra/vms plan
# Review the plan before applying it.
terraform -chdir=infra/vms apply
terraform -chdir=infra/vms output vms
```

No infrastructure is created until `terraform apply` is run with real
Harvester values.

## SSH access

Each collaborator connects with the private key matching their configured
public key:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<VM_IP>
```

The operator can read each address from Terraform and connect directly:

```bash
IS_VM_IP=$(terraform -chdir=infra/vms output -raw is_vm_ip)
DB_VM_IP=$(terraform -chdir=infra/vms output -raw db_vm_ip)
ssh -i ~/.ssh/id_ed25519 ubuntu@"$IS_VM_IP"
ssh -i ~/.ssh/id_ed25519 ubuntu@"$DB_VM_IP"
```

Adding a key to Terraform after a VM has already booted does not reliably rerun
cloud-init. Add all known keys before the first apply. For later access, an
existing administrator should append the new public key to the VM user's
`~/.ssh/authorized_keys`, or the VM should be deliberately reprovisioned after
its data-recovery impact is reviewed.

## Console fallback

Harvester administrators can use `virtctl console <VM_NAME> -n <NAMESPACE>`
with an authorized Harvester kubeconfig when SSH is unavailable. Exit the serial
console with `Ctrl+]`. Console access is an administrative recovery path and is
not a replacement for per-person SSH keys.
