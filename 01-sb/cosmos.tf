# ================================================================================================
# Azure Cosmos DB (SQL API): KeyGen Results Store
# ================================================================================================
# Creates:
#   - Cosmos DB account (SQL / Core API)
#   - SQL database: keygen
#   - SQL container: results
#
# Characteristics:
#   - Partition key: /request_id
#   - TTL enabled (container-level) to mirror DynamoDB TTL behavior
#
# Uses existing:
#   - azurerm provider configuration
#   - azurerm_resource_group.project_rg
#
# Naming:
#   cosmos-keygen-<6-char-random>
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Random suffix for globally-unique Cosmos DB account name
# ------------------------------------------------------------------------------------------------
resource "random_string" "cosmos_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# ------------------------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------------------------
locals {
  cosmos_account_name = "cosmos-keygen-${random_string.cosmos_suffix.result}"
}

# ------------------------------------------------------------------------------------------------
# Cosmos DB Account (SQL / Core API)
# ------------------------------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "keygen" {
  name                = local.cosmos_account_name
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name

  offer_type = "Standard"
  kind       = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.project_rg.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = {
    project = "sb-keygen"
  }
}

# ------------------------------------------------------------------------------------------------
# SQL Database
# ------------------------------------------------------------------------------------------------
resource "azurerm_cosmosdb_sql_database" "keygen" {
  name                = "keygen"
  resource_group_name = azurerm_resource_group.project_rg.name
  account_name        = azurerm_cosmosdb_account.keygen.name
}

resource "azurerm_cosmosdb_sql_container" "results" {
  name                = "results"
  resource_group_name = azurerm_resource_group.project_rg.name
  account_name        = azurerm_cosmosdb_account.keygen.name
  database_name       = azurerm_cosmosdb_sql_database.keygen.name

  # ----------------------------------------------------------------------------------------------
  # Partitioning (newer azurerm provider expects a LIST)
  # ----------------------------------------------------------------------------------------------
  partition_key_paths   = ["/request_id"]
  partition_key_kind    = "Hash"
  partition_key_version = 2

  # ----------------------------------------------------------------------------------------------
  # TTL (seconds)
  #   - -1  = disabled
  #   - > 0 = automatic deletion after N seconds
  # ----------------------------------------------------------------------------------------------
  default_ttl = 3600 # 1 hour

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }


  # ----------------------------------------------------------------------------------------------
  # Lifecycle: Ignore provider/Azure-managed indexing policy normalization
  # ----------------------------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      indexing_policy
    ]
  }
}

# ================================================================================================
# Cosmos DB SQL RBAC: Custom Role for KeyGen Function
# ================================================================================================

resource "azurerm_cosmosdb_sql_role_definition" "keygen_cosmos_role" {
  name                = "KeygenCosmosRole"
  resource_group_name = azurerm_resource_group.project_rg.name
  account_name        = azurerm_cosmosdb_account.keygen.name

  type              = "CustomRole"
  assignable_scopes = [azurerm_cosmosdb_account.keygen.id]

  permissions {
    data_actions = [
      "Microsoft.DocumentDB/databaseAccounts/readMetadata",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*",
    ]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "keygen_cosmos_role_assignment" {
  name = uuidv5(
  "dns",
  "${azurerm_cosmosdb_account.keygen.id}:${azurerm_linux_function_app.keygen_func.identity[0].principal_id}:${azurerm_cosmosdb_sql_role_definition.keygen_cosmos_role.id}"
  )
   
  resource_group_name = azurerm_resource_group.project_rg.name
  account_name        = azurerm_cosmosdb_account.keygen.name

  principal_id       = azurerm_linux_function_app.keygen_func.identity[0].principal_id
  role_definition_id = azurerm_cosmosdb_sql_role_definition.keygen_cosmos_role.id
  scope              = azurerm_cosmosdb_account.keygen.id
}
