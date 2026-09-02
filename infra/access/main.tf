# Mints a namespace-scoped ServiceAccount on Harvester and hands back a kubeconfig
# for it. Everything downstream (infra/vms) runs as that ServiceAccount, so the
# platform team's bootstrap credential is only ever needed for this one module.
#
# The SA is bound to `edit` (kubevirt VM lifecycle) plus `harvesterhci.io:edit`
# (keypairs, VM images, backups) inside our namespace, and to
# `harvesterhci.io:view` on the `default` and `harvester-public` namespaces so it
# can read the shared OS images. It cannot see any other tenant's namespace.
module "vm_access" {
  source = "github.com/wso2/open-cloud-datacenter//modules/addons/harvester-vm-access?ref=terraform/v0.1.7"

  providers = {
    kubernetes.harvester = kubernetes.harvester
  }

  vm_namespace         = var.vm_namespace
  consumer_name        = var.consumer_name
  harvester_api_server = var.harvester_api_server
}
