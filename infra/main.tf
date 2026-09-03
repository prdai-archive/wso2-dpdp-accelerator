# The VM module only emits cloud-init when an SSH key is set. Without cloud-init,
# the guest agent is also absent and Harvester cannot report the VM address.
check "vm_access" {
  assert {
    condition     = length(var.ssh_authorized_keys) > 0
    error_message = "Set ssh_authorized_keys so the VMs receive cloud-init and can be reached over SSH."
  }
}

locals {
  common = {
    namespace           = var.vm_namespace
    image_name          = var.vm_image
    network_name        = var.vm_network
    default_user        = var.vm_user
    ssh_authorized_keys = var.ssh_authorized_keys
  }
}

module "is_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/workloads/vm?ref=v0.8.0"

  name      = "${var.prefix}-is"
  cpu       = var.is_vm_cpu
  memory    = var.is_vm_memory
  disk_size = var.is_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace           = local.common.namespace
  image_name          = local.common.image_name
  network_name        = local.common.network_name
  default_user        = local.common.default_user
  ssh_authorized_keys = local.common.ssh_authorized_keys
}

module "db_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/workloads/vm?ref=v0.8.0"

  name      = "${var.prefix}-db"
  cpu       = var.db_vm_cpu
  memory    = var.db_vm_memory
  disk_size = var.db_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace           = local.common.namespace
  image_name          = local.common.image_name
  network_name        = local.common.network_name
  default_user        = local.common.default_user
  ssh_authorized_keys = local.common.ssh_authorized_keys
}
