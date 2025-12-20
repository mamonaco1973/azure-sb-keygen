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

  sku = "Standard"

  tags = {
    project = "sb-keygen"
  }
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
  default_message_ttl                 = "PT10M"
  dead_lettering_on_message_expiration = true

  # ----------------------------------------------------------------------------------------------
  # Capacity / features
  # ----------------------------------------------------------------------------------------------
  max_size_in_megabytes        = 1024
  requires_duplicate_detection = false
  requires_session            = false
}

# ------------------------------------------------------------------------------------------------
# Queue SAS Authorization Rule (local dev / validate scripts)
# ------------------------------------------------------------------------------------------------
resource "azurerm_servicebus_queue_authorization_rule" "keygen_sas" {
  name     = "keygen-sender-receiver"
  queue_id = azurerm_servicebus_queue.keygen_queue.id

  listen = true
  send   = true
  manage = false
}

# ------------------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------------------
output "servicebus_namespace_name" {
  description = "Auto-generated Service Bus namespace name."
  value       = azurerm_servicebus_namespace.keygen_ns.name
}

output "servicebus_queue_name" {
  description = "Service Bus queue name."
  value       = azurerm_servicebus_queue.keygen_queue.name
}

output "servicebus_queue_connection_string" {
  description = "Queue SAS connection string (local dev only)."
  value       = azurerm_servicebus_queue_authorization_rule.keygen_sas.primary_connection_string
  sensitive   = true
}
