# Both providers read the kubeconfig minted by ../access (see infra/README.md).

provider "harvester" {
  kubeconfig = file(pathexpand(var.harvester_kubeconfig_path))
}

provider "kubernetes" {
  config_path = pathexpand(var.harvester_kubeconfig_path)
}
