#!/bin/bash
# ================================================================================================
# Build Script for Azure Service Bus Deployment
# ================================================================================================
# Purpose:
#   - Validates the local environment before provisioning Azure resources.
#   - Deploys Service Bus–based messaging infrastructure using Terraform.
#   - Packages and deploys Azure Functions application code.
#   - Deploys a static web front end backed by the Functions API.
#   - Fails fast to prevent partial or inconsistent deployments.
#
# Deployment Flow:
#   1. Messaging layer:
#      - Azure Service Bus namespace and messaging entities
#      - Supporting storage account resources
#   2. Compute layer:
#      - Azure Functions application code deployment
#   3. Presentation layer:
#      - Static web application deployment
#
# Notes:
#   - Assumes `az` (Azure CLI) and `terraform` are installed and authenticated.
#   - Assumes `check_env.sh` validates required tools and environment variables.
# ================================================================================================

set -e  # Exit immediately on any unhandled command failure

# ------------------------------------------------------------------------------------------------
# Pre-flight Check: Validate Local Environment
# ------------------------------------------------------------------------------------------------
# - Ensures Azure CLI authentication and subscription context are valid.
# - Verifies Terraform is installed and available in PATH.
# - Confirms required environment variables are present.
# ------------------------------------------------------------------------------------------------
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment validation failed. Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------------------------
# Phase 1: Deploy Service Bus and Storage Resources
# ------------------------------------------------------------------------------------------------
# - Provisions Azure Service Bus namespace and messaging entities.
# - Provisions supporting storage account resources.
# ------------------------------------------------------------------------------------------------
cd 01-sb

terraform init
terraform apply -auto-approve

if [ $? -ne 0 ]; then
  echo "ERROR: Terraform apply failed in 01-sb. Exiting."
  exit 1
fi

cd ..

# ------------------------------------------------------------------------------------------------
# Phase 2: Deploy Azure Functions Application
# ------------------------------------------------------------------------------------------------
# - Packages the Functions application into a ZIP archive.
# - Publishes the application using the Azure CLI.
# ------------------------------------------------------------------------------------------------
cd 02-functions

rm -f app.zip

zip -r app.zip . \
  -x "*.git*" \
  -x "*__pycache__*" \
  -x "*.pytest_cache*" \
  -x "*.venv*" \
  -x "venv/*" \
  -x ".venv/*" \
  -x "*.DS_Store" \
  -x "local.settings.json"

# Discover the Function App name created by Terraform
FunctionAppName=$(az functionapp list \
  --resource-group sb-keygen-rg \
  --query "[?starts_with(name, 'func-keygen-')].name" \
  --output tsv)

# Publish the Functions code using ZIP deployment
az functionapp deployment source config-zip \
  --name "$FunctionAppName" \
  --resource-group sb-keygen-rg \
  --src app.zip \
  --build-remote true

cd ..

# ------------------------------------------------------------------------------------------------
# Phase 3: Deploy Static Web Application
# ------------------------------------------------------------------------------------------------
# - Resolves the Azure Functions API endpoint.
# - Injects the API base URL into the web template.
# - Deploys the static web resources using Terraform.
# ------------------------------------------------------------------------------------------------
URL="https://$(az functionapp show \
  --name "$FunctionAppName" \
  --resource-group sb-keygen-rg \
  --query "defaultHostName" \
  -o tsv)/api"

export API_BASE="${URL}"
echo "NOTE: Function App API URL: ${API_BASE}"

cd 03-webapp || {
  echo "ERROR: 03-webapp directory not found. Exiting."
  exit 1
}

envsubst '${API_BASE}' < index.html.tmpl > index.html || {
  echo "ERROR: Failed to generate index.html. Exiting."
  exit 1
}

terraform init
terraform apply -auto-approve

cd ..

# ------------------------------------------------------------------------------------------------
# Validate the deployment.
# ------------------------------------------------------------------------------------------------

./validate.sh
