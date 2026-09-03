# Data-center infrastructure

Terraform provisions two Ubuntu 24.04 VMs on Harvester using the upstream
[`wso2/open-cloud-datacenter` `workloads/vm` module](https://github.com/wso2/open-cloud-datacenter/tree/main/modules/workloads/vm),
pinned to `v0.8.0`. The configuration follows that module's documented
provider, network, cloud-init, and SSH-key conventions.

| VM | Intended role | vCPU | RAM | Root disk |
| --- | --- | ---: | ---: | ---: |
| `<prefix>-is` | Identity Server | 6 | 12 GiB | 50 GiB |
| `<prefix>-db` | Database | 2 | 4 GiB | 50 GiB |

The split stays within the quoted total of 8 vCPU, 16 GiB RAM, and 100 GiB
storage. This PR only provisions infrastructure and SSH access. It does not
install or configure WSO2 Identity Server, a database, or the accelerator.

## Prerequisites

- Terraform 1.7 or newer
- a Rancher-generated Harvester kubeconfig with rights to create and manage VMs
- the tenant namespace, Ubuntu image, and VM network
- one SSH public key for every person who needs VM access

## Provision the VMs

Copy the variables file and add each collaborator's public key to
`ssh_authorized_keys`. Set `harvester_kubeconfig_path` to the local,
owner-readable kubeconfig file. Keys should be collected through an authenticated
channel; private keys must never be shared.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Set the kubeconfig path, tenant values, and SSH public keys.
make init
make plan
# Review the plan before applying it.
make apply
make ips
```

No infrastructure is created until `terraform apply` is run with a valid
Harvester kubeconfig.

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

The IP targets query the namespace-scoped KubeVirt VM status through `kubectl`.
They do not require cluster-wide CRD permissions, which tenant kubeconfigs do
not have. Override `HARVESTER_KUBECONFIG`, `VM_NAMESPACE`, or `VM_PREFIX` when
your local values differ from the defaults.

## Console access

When the VM subnet is not reachable from the local network, use the serial
console through a separately installed `virtctl` binary. Run the console target:

```bash
make console-is
make console-db
```

These commands set `KUBECONFIG` to `HARVESTER_KUBECONFIG` and invoke `virtctl
console` for the relevant VM. Exit a console session with `Ctrl+]`. Set the
sensitive `vm_console_password` only in ignored local `terraform.tfvars` when
console password access is required; never commit it.

Add every collaborator's public key directly to `ssh_authorized_keys`. At least
one key is required before Terraform can create the VMs.

Adding a key to Terraform after a VM has already booted does not reliably rerun
cloud-init. Add all known keys before the first apply. For later access, an
existing administrator should append the new public key to the VM user's
`~/.ssh/authorized_keys`, or the VM should be deliberately reprovisioned after
its data-recovery impact is reviewed.
