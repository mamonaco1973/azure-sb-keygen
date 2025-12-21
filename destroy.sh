#!/bin/bash
# ================================================================================================
# Destroy Script for Azure Service Bus Deployment
# ================================================================================================
# Purpose:
#   - Tears down the Azure Service Bus demo environment in a controlled manner.
#   - Destroys web app, Service Bus, and supporting storage resources via Terraform.
#   - Fails fast to prevent partial or inconsistent teardown states.
#
# Notes:
#   - USE WITH CAUTION: This permanently deletes Azure resources.
#   - Assumes `az` (Azure CLI) and `terraform` are installed and authenticated.
#   - Destruction order matters if other stacks depend on these resources.
# ================================================================================================

set -e  # Exit immediately if any command fails

# ------------------------------------------------------------------------------------------------
# Phase 1: Destroy Web Application Resources
# ------------------------------------------------------------------------------------------------
# - Removes the Azure web application and related infrastructure.
# - Must run first if the web app depends on Service Bus resources.
# ------------------------------------------------------------------------------------------------
cd 03-webapp

terraform init
terraform destroy -auto-approve

cd ..

# ------------------------------------------------------------------------------------------------
# Phase 2: Destroy Service Bus and Storage Resources
# ------------------------------------------------------------------------------------------------
# - Removes the Azure Service Bus namespace and messaging entities.
# - Removes supporting storage account resources used by this example.
# ------------------------------------------------------------------------------------------------
cd 01-sb

terraform init
terraform destroy -auto-approve

cd ..
