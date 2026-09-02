variable "harvester_bootstrap_kubeconfig" {
  type        = string
  description = "Path to a kubeconfig with enough rights to create a ServiceAccount and ClusterRoleBindings on Harvester. This is the platform team's credential, used once - it is NOT the credential the VMs are later managed with."
}

variable "vm_namespace" {
  type        = string
  description = "Harvester namespace (tenant project namespace) the VMs will live in."
}

variable "consumer_name" {
  type        = string
  description = "Short identifier for this project (lowercase, hyphen-separated). Ends up in the ServiceAccount and RoleBinding names, so it must be unique per namespace."
  default     = "dpdp"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.consumer_name))
    error_message = "consumer_name must be lowercase alphanumeric with hyphens (DNS-1123 subdomain)."
  }
}

variable "harvester_api_server" {
  type        = string
  description = "Direct Harvester Kubernetes API server URL (port 6443, e.g. https://192.168.10.100:6443). Do NOT use the Rancher proxy URL (/k8s/clusters/local) - the minted kubeconfig embeds this address."
}
