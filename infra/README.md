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
- a platform-scoped Harvester kubeconfig with rights to create and manage VMs
- the tenant namespace, Ubuntu image, and VM network
- one SSH public key for every person who needs VM access

## Provision the VMs

Copy the variables file and add each collaborator's public key to
`ssh_authorized_keys`. Keys should be collected through an authenticated channel;
private keys must never be shared.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Set the platform kubeconfig path, tenant values, and SSH public keys.
make init
make plan
# Review the plan before applying it.
make apply
make ips
```

No infrastructure is created until `terraform apply` is run with real
Harvester values.

## SSH access

Each collaborator connects with the private key matching their configured
public key:

```bash
ssh -i ~/.ssh/id_ed25519_dpdp ubuntu@<VM_IP>
```

The Makefile prints each address and opens SSH sessions:

```bash
make is-vm-ip
make db-vm-ip
make ssh-is
make ssh-db
```

Add every collaborator's public key directly to `ssh_authorized_keys`. At least
one key is required before Terraform can create the VMs.

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
