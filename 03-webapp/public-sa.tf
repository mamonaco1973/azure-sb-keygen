# ================================================================================================
# Static Website Storage Account (Public) - Modern AzureRM
# ================================================================================================
# Creates:
#   - Globally-unique Storage account (StorageV2)
#   - Static website configuration (non-deprecated resource)
#   - $web container (explicit)
#   - Uploads ./index.html
#
# Notes:
#   - index.html must exist in the current working directory
#   - Public URL:
#       https://<storage-account>.z##.web.core.windows.net/
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# Random suffix (global uniqueness requirement)
# ------------------------------------------------------------------------------------------------
resource "random_string" "static_suffix" {
  length  = 8
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# ------------------------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------------------------
locals {
  # Storage account names must be 3-24 chars, lowercase letters + numbers only.
  static_site_name = "keygen${random_string.static_suffix.result}"
}

# ------------------------------------------------------------------------------------------------
# Storage account
# ------------------------------------------------------------------------------------------------
resource "azurerm_storage_account" "static_site" {
  name                = local.static_site_name
  resource_group_name = data.azurerm_resource_group.project_rg.name
  location            = data.azurerm_resource_group.project_rg.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version = "TLS1_2"

  tags = {
    project = "static-website"
  }
}

# ------------------------------------------------------------------------------------------------
# Static website configuration (modern replacement for deprecated block)
# ------------------------------------------------------------------------------------------------
resource "azurerm_storage_account_static_website" "static" {
  storage_account_id = azurerm_storage_account.static_site.id

  index_document     = "index.html"
  error_404_document = "404.html"
}

# ------------------------------------------------------------------------------------------------
# $web container (explicit to avoid first-apply race)
# ------------------------------------------------------------------------------------------------
resource "azurerm_storage_container" "web" {
  name                  = "$web"
  storage_account_id   = azurerm_storage_account.static_site.id
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account_static_website.static
  ]
}

# ------------------------------------------------------------------------------------------------
# Upload index.html (from current directory)
# ------------------------------------------------------------------------------------------------
resource "azurerm_storage_blob" "index" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.static_site.name
  storage_container_name = azurerm_storage_container.web.name
  type                   = "Block"

  source       = "${path.root}/index.html"
  content_type = "text/html"

  depends_on = [
    azurerm_storage_container.web
  ]
}

# ------------------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------------------
output "static_site_url" {
  description = "Public base URL for the static website"
  value       = azurerm_storage_account.static_site.primary_web_endpoint
}

output "index_page_url" {
  description = "Direct URL to index.html"
  value       = "${azurerm_storage_account.static_site.primary_web_endpoint}index.html"
}
