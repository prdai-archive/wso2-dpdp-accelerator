terraform {
  required_version = ">= 1.7"

  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "~> 1.7"
    }
    # Not used directly here - the VM module declares it for its optional
    # ScheduledVMBackup resource (kubernetes_manifest), so it has to resolve even
    # while backup_schedule is null.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}
