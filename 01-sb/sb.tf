# sb.tf
# ================================================================================================
# Azure Service Bus: Namespace + Queue (KeyGen)
# ================================================================================================
# Creates:
#   - Service Bus namespace with auto-generated unique name
#   - Service Bus queue
#   - Queue SAS auth rule (send/listen) for local dev / validation
#
# Uses existing:
#   - azurerm provider configuration
#   - azurerm_resource_group.project_rg
#
# Naming:
#   sb-keygen-<6-char-random>
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Random suffix for globally-unique namespace name
# ------------------------------------------------------------------------------------------------
resource "random_string" "sb_suffix" {
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
  servicebus_namespace_name = "sb-keygen-${random_string.sb_suffix.result}"
}

# ------------------------------------------------------------------------------------------------
# Service Bus Namespace
# ------------------------------------------------------------------------------------------------
resource "azurerm_servicebus_namespace" "keygen_ns" {
  name                = local.servicebus_namespace_name
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  sku                 = "Standard"
  local_auth_enabled  = false
}

# ------------------------------------------------------------------------------------------------
# Service Bus Queue
# ------------------------------------------------------------------------------------------------
resource "azurerm_servicebus_queue" "keygen_queue" {
  name         = "keygen-requests"
  namespace_id = azurerm_servicebus_namespace.keygen_ns.id

  # ----------------------------------------------------------------------------------------------
  # Reliability / retry behavior
  # ----------------------------------------------------------------------------------------------
  max_delivery_count = 10
  lock_duration      = "PT1M"

  # ----------------------------------------------------------------------------------------------
  # TTL + DLQ behavior
  # ----------------------------------------------------------------------------------------------
  default_message_ttl                  = "PT10M"
  dead_lettering_on_message_expiration = true

  # ----------------------------------------------------------------------------------------------
  # Capacity / features
  # ----------------------------------------------------------------------------------------------
  max_size_in_megabytes        = 1024
  requires_duplicate_detection = false
  requires_session             = false
}


resource "azurerm_role_assignment" "sb_sender" {
  scope                = azurerm_servicebus_queue.keygen_queue.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_linux_function_app.keygen_func.identity[0].principal_id
}

resource "azurerm_role_assignment" "sb_receiver" {
  scope                = azurerm_servicebus_queue.keygen_queue.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.keygen_func.identity[0].principal_id
}

