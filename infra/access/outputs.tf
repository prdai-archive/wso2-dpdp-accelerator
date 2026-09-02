# Sensitive: this kubeconfig carries a long-lived ServiceAccount token. It is
# deliberately not written to disk by Terraform - `make access` writes it with a
# 0600 umask instead, because a checked-in (or world-readable) copy would leak a
# credential that outlives any operator's own access.
output "kubeconfig" {
  description = "Kubeconfig for the namespace-scoped ServiceAccount. Consumed by infra/vms. Handle as a secret."
  value       = module.vm_access.kubeconfig
  sensitive   = true
}

output "service_account_name" {
  description = "ServiceAccount created in the tenant namespace."
  value       = module.vm_access.service_account_name
}

output "consumer_name" {
  description = "Consumer identifier this kubeconfig was minted for."
  value       = var.consumer_name
}
