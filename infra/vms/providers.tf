# Both providers use the platform-scoped Harvester kubeconfig supplied as input.

provider "harvester" {
  kubeconfig = file(pathexpand(var.harvester_kubeconfig_path))
}

provider "kubernetes" {
  config_path = pathexpand(var.harvester_kubeconfig_path)
}
