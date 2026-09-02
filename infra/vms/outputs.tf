output "vms" {
  description = "Both VMs, keyed by role. `null` IP means the lease had not been reported yet - re-run terraform refresh."
  value = {
    is = {
      name = module.is_vm.vm_name
      id   = module.is_vm.vm_id
      ip   = try(module.is_vm.ip_addresses[0], null)
    }
    db = {
      name = module.db_vm.vm_name
      id   = module.db_vm.vm_id
      ip   = try(module.db_vm.ip_addresses[0], null)
    }
  }
}

output "is_vm_ip" {
  description = "IP of the Identity Server VM."
  value       = try(module.is_vm.ip_addresses[0], null)
}

output "db_vm_ip" {
  description = "IP of the MySQL VM."
  value       = try(module.db_vm.ip_addresses[0], null)
}

output "ssh_user" {
  description = "OS user created by cloud-init on both VMs."
  value       = var.vm_user
}
