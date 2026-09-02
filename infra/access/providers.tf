# The upstream module takes its provider as a configuration alias, so the
# bootstrap credential has to be bound to `kubernetes.harvester` here rather
# than to the default (unaliased) kubernetes provider.
provider "kubernetes" {
  alias = "harvester"

  config_path = pathexpand(var.harvester_bootstrap_kubeconfig)
}
