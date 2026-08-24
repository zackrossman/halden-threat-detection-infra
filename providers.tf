provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id = var.subscription_id
}

# The Kubernetes provider borrows the credentials of the AKS cluster this
# service is deployed into. The cluster itself is owned by the platform team and
# created outside this configuration.
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.platform.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.platform.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.platform.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)
}
