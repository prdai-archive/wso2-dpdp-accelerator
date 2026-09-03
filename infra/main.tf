check "console_access" {
  assert {
    condition     = var.vm_console_password != null
    error_message = "Set vm_console_password so the VMs receive cloud-init and can be accessed through the serial console."
  }
}

locals {
  common = {
    namespace    = var.vm_namespace
    image_name   = var.vm_image
    network_name = var.vm_network
    default_user = var.vm_user
    password     = var.vm_console_password
  }
}

module "is_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/workloads/vm?ref=v0.8.0"

  name      = "${var.prefix}-is"
  cpu       = var.is_vm_cpu
  memory    = var.is_vm_memory
  disk_size = var.is_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace    = local.common.namespace
  image_name   = local.common.image_name
  network_name = local.common.network_name
  default_user = local.common.default_user
  password     = local.common.password
}

module "db_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/workloads/vm?ref=v0.8.0"

  name      = "${var.prefix}-db"
  cpu       = var.db_vm_cpu
  memory    = var.db_vm_memory
  disk_size = var.db_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace    = local.common.namespace
  image_name   = local.common.image_name
  network_name = local.common.network_name
  default_user = local.common.default_user
  password     = local.common.password
}
