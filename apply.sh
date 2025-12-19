#!/bin/bash
# ================================================================================
# Build Script for Azure Service Bus Deployment
#
# Purpose:
#   - Validates the local environment and required tooling before provisioning.
#   - Deploys Azure messaging infrastructure using Terraform.
#   - Provisions core Azure resources for Service Bus–based workloads.
#   - Ensures failures are caught early with explicit exit conditions.
#
# Deployment Flow:
#   1. Messaging layer:
#      - Azure Service Bus namespace
#      - Service Bus entities (queues / topics as defined in Terraform)
#      - Supporting storage account resources
#
# Notes:
#   - Assumes `az` (Azure CLI) and `terraform` are installed and authenticated.
#   - Assumes `check_env.sh` validates required environment variables and tools.
# ================================================================================


set -e  # Exit immediately on any unhandled command failure

# --------------------------------------------------------------------------------------------------
# Pre-flight Check: Validate environment
# Runs custom environment validation script (`check_env.sh`) to ensure:
#   - Azure CLI is logged in and subscription is set
#   - Terraform is installed
#   - Required variables (subscription ID, tenant ID, etc.) are present
# --------------------------------------------------------------------------------------------------
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

# --------------------------------------------------------------------------------------------------
# Phase 1: Deploy servce bus and storage account
# --------------------------------------------------------------------------------------------------
cd 01-sb

terraform init   # Initialize Terraform working directory (download providers/modules)
terraform apply -auto-approve   # Deploy Key Vault and other directory resources

# Error handling for Terraform apply
if [ $? -ne 0 ]; then
  echo "ERROR: Terraform apply failed in 01-sb. Exiting."
  exit 1
fi
cd ..

