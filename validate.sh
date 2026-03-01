#!/bin/bash
# ==============================================================================
# validate.sh - KeyGen Quick Start Validation
# ------------------------------------------------------------------------------
# Purpose:
#   - Discover Azure Function App endpoint via Azure CLI.
#   - Retrieve static website URL from Terraform output.
#   - Submit keygen request and validate async processing.
#   - Print quick-start endpoints for testing.
#
# Fast-Fail Behavior:
#   - Script exits immediately on command failure, unset variables,
#     or failed pipelines.
#
# Requirements:
#   - curl, jq, Terraform, and Azure CLI installed and authenticated.
#   - Terraform deployment completed successfully.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
RESOURCE_GROUP="${RESOURCE_GROUP:-sb-keygen-rg}"

# ------------------------------------------------------------------------------
# Step 0: Retrieve static website URL from Terraform
# ------------------------------------------------------------------------------
cd ./03-webapp || exit 1
website_url="$(terraform output -raw index_page_url)"
cd ..

# ------------------------------------------------------------------------------
# Step 1: Discover Azure Function App endpoint
# ------------------------------------------------------------------------------
echo "NOTE: Locating Azure Function App endpoint..."

function_app_name="$(az functionapp list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?starts_with(name, 'func-keygen-')].name | [0]" \
  --output tsv)"

if [[ -z "${function_app_name}" || "${function_app_name}" == "None" ]]; then
  echo "ERROR: No Function App found with prefix 'func-keygen-' in RG '${RESOURCE_GROUP}'"
  exit 1
fi

default_host_name="$(az functionapp show \
  --name "${function_app_name}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" \
  --output tsv)"

if [[ -z "${default_host_name}" || "${default_host_name}" == "None" ]]; then
  echo "ERROR: Unable to determine Function App hostname."
  exit 1
fi

api_url="https://${default_host_name}/api"
echo "NOTE: Function App URL - ${api_url}"

# ------------------------------------------------------------------------------
# Step 2: Submit SSH key generation request
# ------------------------------------------------------------------------------
KEY_TYPE="${KEY_TYPE:-rsa}"
KEY_BITS="${KEY_BITS:-2048}"

req_payload="$(
  jq -n \
    --arg kt "${KEY_TYPE}" \
    --arg kb "${KEY_BITS}" \
    '{ key_type: $kt, key_bits: ($kb | tonumber) }'
)"

echo "NOTE: Sending request - key_type=${KEY_TYPE}, key_bits=${KEY_BITS}"

response="$(
  curl -s -X POST "${api_url}/keygen" \
    -H "Content-Type: application/json" \
    -d "${req_payload}"
)"

request_id="$(echo "${response}" | jq -r '.request_id // empty')"

if [[ -z "${request_id}" ]]; then
  echo "ERROR: No request_id returned."
  echo "NOTE: Response was: ${response}"
  exit 1
fi

echo "NOTE: Submitted keygen request (${request_id})."
echo "NOTE: Polling for result..."

# ------------------------------------------------------------------------------
# Step 3: Poll result endpoint until complete
# ------------------------------------------------------------------------------
MAX_ATTEMPTS=30
SLEEP_SECONDS=2

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  result="$(curl -s "${api_url}/result/${request_id}")"
  status="$(echo "${result}" | jq -r '.status // empty')"

  if [[ "${status}" == "complete" ]]; then
    echo "NOTE: Key generation complete."
    break
  fi

  if [[ "${status}" == "error" ]]; then
    echo "ERROR: Service reported an error."
    echo "${result}" | jq
    exit 1
  fi

  echo "NOTE: Attempt ${i}/${MAX_ATTEMPTS}: pending..."
  sleep "${SLEEP_SECONDS}"

  if [[ "${i}" -eq "${MAX_ATTEMPTS}" ]]; then
    echo "ERROR: Key generation did not complete."
    exit 1
  fi
done

# ------------------------------------------------------------------------------
# Final Quick Start Output
# ------------------------------------------------------------------------------
echo ""
echo "============================================================================"
echo "Azure Service Bus Quick Start - Validation Output"
echo "============================================================================"
echo ""

if [ -n "${website_url}" ] && [ "${website_url}" != "None" ]; then
  echo "NOTE: Test Web URL:    ${website_url}"
else
  echo "WARN: Static website URL not found"
fi

if [ -n "${api_url}" ] && [ "${api_url}" != "None" ]; then
  echo "NOTE: API Base URI:    ${api_url}"
else
  echo "WARN: Function App endpoint not found"
fi

echo ""
echo "NOTE: Validation complete."
echo ""