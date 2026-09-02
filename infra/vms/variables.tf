variable "harvester_kubeconfig_path" {
  type        = string
  description = "Path to the kubeconfig minted by ../access. Relative to infra/vms, which is where terraform runs from."
  default     = "../../kube-config/harvester.yaml"
}

variable "prefix" {
  type        = string
  description = "Prefix for the VM names, giving <prefix>-is and <prefix>-db."
  default     = "dpdp"
}

variable "vm_namespace" {
  type        = string
  description = "Harvester namespace (tenant project namespace) to create the VMs in. Must match the namespace ../access was run against."
}

variable "vm_image" {
  type        = string
  description = "Harvester OS image in namespace/name form. Ask the platform team which images your namespace can read."
}

variable "vm_network" {
  type        = string
  description = "Harvester network attachment definition in namespace/name form. Ask the platform team which subnet your namespace is on."
}

variable "vm_user" {
  type        = string
  description = "OS user created by cloud-init on both VMs. Everything under scripts/ logs in as this user."
  default     = "ubuntu"
}

variable "vm_password" {
  type        = string
  description = "Password for vm_user. Leave null to allow key-only SSH; set it if you want console/password access as a fallback."
  default     = null
  sensitive   = true
}

variable "ssh_authorized_keys" {
  type        = list(string)
  description = "SSH public keys authorised for vm_user on both VMs. This is what `make ssh-is` / `make ssh-db` use."
  default     = []
}

variable "ssh_public_key_path" {
  type        = string
  description = "Optional path to one SSH public key. Tilde expansion happens inside the module, unlike file() in a tfvars file."
  default     = null
}

# The quoted 8 vCPU / 16 GiB / 100 GiB allocation is split across both VMs.
# IS receives most compute because it runs the JVM, Carbon, and the portal; the
# database receives half the disk because it owns the persistent application data.

variable "is_vm_cpu" {
  type        = number
  description = "vCPUs for the Identity Server VM."
  default     = 6
}

variable "is_vm_memory" {
  type        = string
  description = "RAM for the Identity Server VM, in Gi."
  default     = "12Gi"
}

variable "is_vm_disk_size" {
  type        = string
  description = "Root disk for the Identity Server VM."
  default     = "50Gi"
}

variable "db_vm_cpu" {
  type        = number
  description = "vCPUs for the MySQL VM."
  default     = 2
}

variable "db_vm_memory" {
  type        = string
  description = "RAM for the MySQL VM, in Gi."
  default     = "4Gi"
}

variable "db_vm_disk_size" {
  type        = string
  description = "Root disk for the MySQL VM. Holds the MySQL data directory."
  default     = "50Gi"
}
