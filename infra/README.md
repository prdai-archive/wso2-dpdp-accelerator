# Data-center deployment

This directory provisions two Ubuntu 24.04 VMs on Harvester with the
[`wso2/open-cloud-datacenter`](https://github.com/wso2/open-cloud-datacenter)
Terraform modules pinned to `terraform/v0.1.7`.

| VM | Purpose | vCPU | RAM | Root disk |
| --- | --- | ---: | ---: | ---: |
| `<prefix>-is` | WSO2 Identity Server 7.3.0 and the DPDP accelerator | 6 | 12 GiB | 50 GiB |
| `<prefix>-db` | MySQL and all IS/accelerator databases | 2 | 4 GiB | 50 GiB |

The split stays within the quoted total of 8 vCPU, 16 GiB RAM, and 100 GiB
storage. IS receives most compute for the JVM and portal; MySQL receives half
the storage because it owns the persistent deployment data. These defaults are
appropriate for the current demonstration deployment, not a production HA
topology.

## Prerequisites

- Terraform 1.7 or newer and ShellCheck, or `devbox shell`
- a Harvester bootstrap kubeconfig that can create namespace access
- the Harvester API address, tenant namespace, Ubuntu image, and VM network
- an Ed25519 SSH key pair (or another public key configured in tfvars)
- JDK 21 and Maven on the operator machine to build the accelerator

## 1. Create namespace-scoped access

The bootstrap kubeconfig is used only by `infra/access`. The resulting
long-lived service-account credential is written to the git-ignored
`kube-config/harvester.yaml` with mode 0600.

```bash
cp infra/access/terraform.tfvars.example infra/access/terraform.tfvars
# Fill in every REPLACE value.
make access-plan
make access-apply
```

## 2. Plan and create the VMs

```bash
cp infra/vms/terraform.tfvars.example infra/vms/terraform.tfvars
# Fill in the tenant values and point ssh_public_key_path at your .pub file.
make vms-plan
# Only after reviewing the plan:
make vms-apply
make ips
```

No infrastructure has been applied by this repository change. Harvester must
return IP leases before the next stage can run.

## 3. Configure SSH and deploy

Build the accelerator, copy the environment template, and paste the two IPs
from `make ips` into `.env`.

```bash
mvn clean install
cp .env.example .env
make ssh-is
make ssh-db
make setup
```

`make setup` installs MySQL on the database VM, installs WSO2 IS 7.3.0 on the
application VM, applies the schemas only to empty databases, installs the built
accelerator, and registers IS as a systemd service. Re-running it preserves
existing database contents.

Secrets remain in the local `.env`, `secret.tfvars`, Terraform state, and
kubeconfig files. All are ignored by Git. Terraform state still contains
sensitive values, so keep it in protected storage and do not share it.
