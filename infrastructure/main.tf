# Terraform configuration for a secure, serverless Azure Resume solution.
# This file defines all necessary Azure resources and configures them
# with best practices like Managed Identities and Key Vault integration.

# --- Terraform and Provider Configuration ---

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }

  # This block configures Terraform to store its state file remotely in the
  # Azure Storage Account you created earlier. This is essential for CI/CD.
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    # IMPORTANT: Replace this with the name of your Terraform state storage account
    storage_account_name = "tfstateresumeglds05"
    container_name       = "tfstate"
    key                  = "azure-resume.tfstate"
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
}


# --- Resource Definitions ---

# A random string to ensure globally unique names for resources
resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

# 1. Main Resource Group for the application
resource "azurerm_resource_group" "rg" {
  name     = "AzureResumeRG-Terraform"
  location = "eastus2"
}

# 2. Monitoring Resources (Application Insights)
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "logs-resume-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "insights" {
  name                = "insights-resume-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.logs.id
  application_type    = "web"
}

# 3. Storage Account for Frontend Hosting
resource "azurerm_storage_account" "sa" {
  name                     = "resumesa${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Enable the static website hosting feature
  static_website {
    index_document     = "index.html"
    error_404_document = "index.html"
  }
}

# 4. Key Vault for Secure Secret Storage
resource "azurerm_key_vault" "kv" {
  name                        = "kv-resume-${random_string.unique.result}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization = true
}

# Data source to get information about the current Azure AD user/SP
data "azurerm_client_config" "current" {}

# 5. Backend Compute (Function App)
resource "azurerm_service_plan" "plan" {
  name                = "plan-resume-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan
}

resource "azurerm_linux_function_app" "func" {
  name                = "func-resume-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  storage_account_name = azurerm_storage_account.sa.name
  service_plan_id     = azurerm_service_plan.plan.id

  # Enable System-Assigned Managed Identity
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"          = "~4"
    "FUNCTIONS_WORKER_RUNTIME"             = "python"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.insights.connection_string
    # Reference to Key Vault for the Cosmos DB connection string
    "CosmosDbConnectionString"             = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=CosmosDbConnectionString)"
  }
}

# 6. Security (RBAC for Key Vault)
# Grant the Function App's Managed Identity permission to read secrets from Key Vault
resource "azurerm_role_assignment" "func_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}


# === OUTPUTS ===
# These values are returned after deployment and can be used in the CI/CD pipeline.

output "function_app_name" {
  value = azurerm_linux_function_app.func.name
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "website_url" {
  value = azurerm_storage_account.sa.primary_web_endpoint
}
