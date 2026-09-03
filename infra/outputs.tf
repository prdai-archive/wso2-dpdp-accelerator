output "vms" {
  description = "Both VMs, keyed by role. Use the Makefile IP targets to query the guest addresses."
  value = {
    is = {
      name = module.is_vm.vm_name
      id   = module.is_vm.vm_id
    }
    db = {
      name = module.db_vm.vm_name
      id   = module.db_vm.vm_id
    }
  }
}

output "ssh_user" {
  description = "OS user created by cloud-init on both VMs."
  value       = var.vm_user
}
