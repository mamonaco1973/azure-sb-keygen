# ================================================================================================
# Azure Functions (Linux Consumption) for SB KeyGen Service
# ================================================================================================
# Creates:
#   - Storage account (required by Functions)
#   - App Service plan (Consumption / Y1)
#   - Application Insights (logging)
#   - Linux Function App (Python 3.11) with system-assigned identity
#
# Uses existing:
#   - azurerm provider config (already in your root)
#   - azurerm_resource_group.project_rg (already created)
#
# Notes:
#   - This only creates the hosting infrastructure. Code deployment comes next.
#   - App settings are wired to your existing Service Bus + Cosmos resources
#     (assumes the resource names from our sb.tf and cosmos.tf).
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Random suffixes
# ------------------------------------------------------------------------------------------------
resource "random_string" "func_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "random_string" "sa_suffix" {
  length  = 12
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# ------------------------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------------------------
locals {
  func_app_name = "func-keygen-${random_string.func_suffix.result}"
  plan_name     = "plan-keygen-${random_string.func_suffix.result}"

  # Storage account names must be 3-24 chars, lowercase letters + numbers only.
  storage_name = "sakeygen${random_string.sa_suffix.result}"

  ai_name = "ai-keygen-${random_string.func_suffix.result}"
}

# ------------------------------------------------------------------------------------------------
# Storage account (Functions requirement)
# ------------------------------------------------------------------------------------------------
resource "azurerm_storage_account" "func_sa" {
  name                = local.storage_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version = "TLS1_2"

  tags = {
    project = "sb-keygen"
  }
}

# ------------------------------------------------------------------------------------------------
# Consumption plan (Linux)
# ------------------------------------------------------------------------------------------------
resource "azurerm_service_plan" "func_plan" {
  name                = local.plan_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  os_type  = "Linux"
  sku_name = "Y1" # Consumption
}

# ------------------------------------------------------------------------------------------------
# Application Insights
# ------------------------------------------------------------------------------------------------
resource "azurerm_application_insights" "func_ai" {
  name                = local.ai_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  application_type = "web"

  tags = {
    project = "sb-keygen"
  }
}

# ------------------------------------------------------------------------------------------------
# Linux Function App (Python)
# ------------------------------------------------------------------------------------------------
resource "azurerm_linux_function_app" "keygen_func" {
  name                = local.func_app_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  service_plan_id = azurerm_service_plan.func_plan.id

  storage_account_name       = azurerm_storage_account.func_sa.name
  storage_account_access_key = azurerm_storage_account.func_sa.primary_access_key

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  # ----------------------------------------------------------------------------------------------
  # App settings (wire to your existing SB + Cosmos from sb.tf and cosmos.tf)
  # ----------------------------------------------------------------------------------------------
  app_settings = {
    FUNCTIONS_EXTENSION_VERSION = "~4"
    FUNCTIONS_WORKER_RUNTIME    = "python"

    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.func_ai.connection_string

    # ----------------------------
    # Service Bus (RBAC)
    # ----------------------------
    SERVICEBUS_QUEUE_NAME                         = azurerm_servicebus_queue.keygen_queue.name
    SERVICEBUS_NAMESPACE_FQDN                     = "${azurerm_servicebus_namespace.keygen_ns.name}.servicebus.windows.net"
    ServiceBusConnection__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.keygen_ns.name}.servicebus.windows.net"

    # ----------------------------
    # Cosmos DB (RBAC)
    # ----------------------------
    COSMOS_ENDPOINT       = azurerm_cosmosdb_account.keygen.endpoint
    COSMOS_DATABASE_NAME  = azurerm_cosmosdb_sql_database.keygen.name
    COSMOS_CONTAINER_NAME = azurerm_cosmosdb_sql_container.results.name
  }

  lifecycle {
    ignore_changes = [
      app_settings["APPLICATIONINSIGHTS_CONNECTION_STRING"],
      app_settings["FUNCTIONS_EXTENSION_VERSION"],
      app_settings["SCM_DO_BUILD_DURING_DEPLOYMENT"],
      site_config[0].application_insights_connection_string
    ]
  }
}
