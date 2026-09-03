provider "harvester" {
  kubeconfig = pathexpand(var.harvester_kubeconfig_path)
}

provider "kubernetes" {
  config_path = pathexpand(var.harvester_kubeconfig_path)
}
