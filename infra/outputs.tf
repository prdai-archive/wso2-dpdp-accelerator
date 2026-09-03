data "kubernetes_resource" "is_vmi" {
  api_version = "kubevirt.io/v1"
  kind        = "VirtualMachineInstance"

  metadata {
    name      = module.is_vm.vm_name
    namespace = var.vm_namespace
  }

  depends_on = [module.is_vm]
}

data "kubernetes_resource" "db_vmi" {
  api_version = "kubevirt.io/v1"
  kind        = "VirtualMachineInstance"

  metadata {
    name      = module.db_vm.vm_name
    namespace = var.vm_namespace
  }

  depends_on = [module.db_vm]
}

output "vms" {
  description = "Both VMs, keyed by role. `null` IP means the guest has not reported an address yet."
  value = {
    is = {
      name = module.is_vm.vm_name
      id   = module.is_vm.vm_id
      ip   = try(data.kubernetes_resource.is_vmi.object.status.interfaces[0].ipAddress, null)
    }
    db = {
      name = module.db_vm.vm_name
      id   = module.db_vm.vm_id
      ip   = try(data.kubernetes_resource.db_vmi.object.status.interfaces[0].ipAddress, null)
    }
  }
}

output "is_vm_ip" {
  description = "IP of the Identity Server VM."
  value       = try(data.kubernetes_resource.is_vmi.object.status.interfaces[0].ipAddress, null)
}

output "db_vm_ip" {
  description = "IP of the MySQL VM."
  value       = try(data.kubernetes_resource.db_vmi.object.status.interfaces[0].ipAddress, null)
}

output "ssh_user" {
  description = "OS user created by cloud-init on both VMs."
  value       = var.vm_user
}
