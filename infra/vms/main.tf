# The VM module only emits cloud-init when at least one of password /
# ssh_authorized_keys is set. With neither, there is no qemu-guest-agent either,
# so `wait_for_lease` would never see an IP and apply would hang until timeout -
# worth failing on up front rather than 10 minutes into a plan.
check "vm_access" {
  assert {
    condition     = length(var.ssh_authorized_keys) > 0 || var.ssh_public_key_path != null || var.vm_password != null
    error_message = "Set ssh_public_key_path, ssh_authorized_keys, and/or vm_password: with none, the VM gets no cloud-init or qemu-guest-agent."
  }
}

locals {
  ssh_authorized_keys = concat(
    var.ssh_authorized_keys,
    var.ssh_public_key_path == null ? [] : [trimspace(file(pathexpand(var.ssh_public_key_path)))]
  )

  common = {
    namespace           = var.vm_namespace
    image_name          = var.vm_image
    network_name        = var.vm_network
    default_user        = var.vm_user
    password            = var.vm_password
    ssh_authorized_keys = local.ssh_authorized_keys
  }
}

module "is_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/tenancy/vm?ref=terraform/v0.1.7"

  name      = "${var.prefix}-is"
  cpu       = var.is_vm_cpu
  memory    = var.is_vm_memory
  disk_size = var.is_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace           = local.common.namespace
  image_name          = local.common.image_name
  network_name        = local.common.network_name
  default_user        = local.common.default_user
  password            = local.common.password
  ssh_authorized_keys = local.common.ssh_authorized_keys
}

module "db_vm" {
  source = "github.com/wso2/open-cloud-datacenter//modules/tenancy/vm?ref=terraform/v0.1.7"

  name      = "${var.prefix}-db"
  cpu       = var.db_vm_cpu
  memory    = var.db_vm_memory
  disk_size = var.db_vm_disk_size

  run_strategy = "RerunOnFailure"

  namespace           = local.common.namespace
  image_name          = local.common.image_name
  network_name        = local.common.network_name
  default_user        = local.common.default_user
  password            = local.common.password
  ssh_authorized_keys = local.common.ssh_authorized_keys
}
