terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }

  # Remote state lives in the platform team's Terraform state storage account.
  # Values are supplied at init time rather than committed here:
  #
  #   terraform init \
  #     -backend-config="resource_group_name=CHANGE_ME" \
  #     -backend-config="storage_account_name=CHANGE_ME" \
  #     -backend-config="container_name=CHANGE_ME" \
  #     -backend-config="key=threat-detection/production.tfstate"
  backend "azurerm" {
    # resource_group_name  = "CHANGE_ME"
    # storage_account_name = "CHANGE_ME"
    # container_name       = "CHANGE_ME"
    # key                  = "threat-detection/production.tfstate"
    use_azuread_auth = true
  }
}
