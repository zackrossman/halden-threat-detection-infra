locals {
  service_name = "halden-threat-detection"
  name_prefix  = "halden-threat-detection-${var.environment}"

  common_tags = merge(
    {
      service     = local.service_name
      environment = var.environment
      owner       = "detection-platform"
      managed_by  = "terraform"
      source_repo = "halden-threat-detection-infra"
    },
    var.tags,
  )

  labels = {
    "app.kubernetes.io/name"       = local.service_name
    "app.kubernetes.io/part-of"    = "halden"
    "app.kubernetes.io/component"  = "api"
    "app.kubernetes.io/managed-by" = "terraform"
    "halden.io/environment"        = var.environment
  }
}

data "azurerm_resource_group" "platform" {
  name = var.resource_group_name
}

# The cluster is provisioned and upgraded by the platform team in their own
# configuration. This service only rents space on it.
data "azurerm_kubernetes_cluster" "platform" {
  name                = var.cluster_name
  resource_group_name = data.azurerm_resource_group.platform.name
}

resource "kubernetes_namespace" "halden" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/part-of" = "halden"
      "halden.io/environment"     = var.environment
    }
  }
}
