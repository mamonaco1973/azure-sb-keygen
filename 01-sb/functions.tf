# =============================================================================
# Azure Functions (Flex Consumption) for SB KeyGen Service
# =============================================================================
# Creates:
#   - Storage account (Functions requirement)
#   - Blob container (Flex requirement for code deployments)
#   - App Service plan (Flex Consumption / FC1)
#   - Application Insights (logging)
#   - Flex Function App (Python) w/ system-assigned identity
#
# Uses existing:
#   - azurerm provider config (in your root)
#   - azurerm_resource_group.project_rg (already created)
#
# Notes:
#   - Flex Consumption replaces Linux Consumption (Y1).
#   - This creates hosting infra only. Code deployment comes next.
#   - App settings reference existing Service Bus + Cosmos resources.
# =============================================================================

# -----------------------------------------------------------------------------
# Random suffixes
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  func_app_name = "func-keygen-${random_string.func_suffix.result}"
  plan_name     = "plan-keygen-${random_string.func_suffix.result}"

  # Storage account names: 3-24 chars, lowercase letters + numbers only.
  storage_name = "sakeygen${random_string.sa_suffix.result}"

  ai_name = "ai-keygen-${random_string.func_suffix.result}"

  # Flex uses a blob container for code deployments.
  code_container_name = "func-code"
}

# -----------------------------------------------------------------------------
# Storage account (Functions requirement)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Storage container (Flex requirement)
# -----------------------------------------------------------------------------
resource "azurerm_storage_container" "func_code" {
  name                  = local.code_container_name
  storage_account_id    = azurerm_storage_account.func_sa.id
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# Flex Consumption plan (Linux)
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "func_plan" {
  name                = local.plan_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  os_type  = "Linux"
  sku_name = "FC1" # Flex Consumption
}

# -----------------------------------------------------------------------------
# Application Insights
# -----------------------------------------------------------------------------
resource "azurerm_application_insights" "func_ai" {
  name                = local.ai_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  application_type = "web"

  tags = {
    project = "sb-keygen"
  }
}

# -----------------------------------------------------------------------------
# Flex Function App (Python)
# -----------------------------------------------------------------------------
resource "azurerm_function_app_flex_consumption" "keygen_func" {
  name                = local.func_app_name
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location

  service_plan_id = azurerm_service_plan.func_plan.id

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # Flex storage wiring (blob container endpoint for code deployments)
  # ---------------------------------------------------------------------------
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func_sa.primary_blob_endpoint}${azurerm_storage_container.func_code.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.func_sa.primary_access_key

  # ---------------------------------------------------------------------------
  # Runtime
  # ---------------------------------------------------------------------------
  runtime_name    = "python"
  runtime_version = "3.11"

  # ---------------------------------------------------------------------------
  # Scaling and sizing (tune as needed)
  # ---------------------------------------------------------------------------
  maximum_instance_count = 50
  instance_memory_in_mb  = 2048

  site_config {
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
  }

  # ---------------------------------------------------------------------------
  # App settings (wire to SB + Cosmos from sb.tf and cosmos.tf)
  # ---------------------------------------------------------------------------
  app_settings = {
    # Flex rejects FUNCTIONS_WORKER_RUNTIME. Do not set it here.
    FUNCTIONS_EXTENSION_VERSION = "~4"

    APPLICATIONINSIGHTS_CONNECTION_STRING =
      azurerm_application_insights.func_ai.connection_string

    # ----------------------------
    # Service Bus (RBAC)
    # ----------------------------
    SERVICEBUS_QUEUE_NAME = azurerm_servicebus_queue.keygen_queue.name

    SERVICEBUS_NAMESPACE_FQDN =
      "${azurerm_servicebus_namespace.keygen_ns.name}.servicebus.windows.net"

    ServiceBusConnection__fullyQualifiedNamespace =
      "${azurerm_servicebus_namespace.keygen_ns.name}.servicebus.windows.net"

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
    ]
  }
}