#!/bin/bash
# ================================================================================
# Destroy Script for Azure Service Bus Deployment
#
# Purpose:
#   - Tears down the Service Bus environment in a safe, repeatable way.
#   - Destroys Azure Service Bus and supporting storage resources via Terraform.
#   - Ensures failures are caught early with explicit exit behavior.
#
# Notes:
#   - Use with caution: this permanently deletes deployed Azure resources.
#   - Assumes `az` (Azure CLI) and `terraform` are installed and authenticated.
#   - Order matters if other stacks depend on these resources.
# ================================================================================

set -e  # Exit immediately if any command fails

# --------------------------------------------------------------------------------
# Phase 1: Destroy Service Bus and Storage Account
# --------------------------------------------------------------------------------
# - Removes Azure Service Bus namespace and entities defined in Terraform.
# - Removes supporting storage account resources created for this example.
# --------------------------------------------------------------------------------
cd 01-sb

terraform init
terraform destroy -auto-approve  # Destroy Service Bus + storage resources

cd ..
