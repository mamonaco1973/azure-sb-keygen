#!/bin/bash
# ================================================================================================
# File: validate.sh
# ================================================================================================
# Purpose:
#   End-to-end validation for the Azure Service Bus KeyGen microservice.
#   - Discovers the deployed Azure Function App endpoint via Azure CLI.
#   - Submits a key generation request to the HTTP-triggered Function endpoint.
#   - Parses the returned request_id.
#   - Polls the result endpoint until the generated SSH keypair is available.
#
# Requirements:
#   - curl, jq, and Azure CLI installed and authenticated.
#   - Terraform deployment of the Azure Function App completed successfully.
#   - Resource group name matches the deployment (default used here: sb-keygen-rg).
#   - Optional env vars:
#       KEY_TYPE = rsa | ed25519            (default: rsa)
#       KEY_BITS = 2048 | 4096 (RSA only)   (default: 2048)
#
# Notes:
#   - This script assumes your Function App exposes:
#       POST /api/keygen
#       GET  /api/result/{request_id}
#   - If your Function App requires a function key, you must include it (x-functions-key
#     header or ?code= query string), and your CORS settings must allow your caller.
# ================================================================================================
set -euo pipefail

cd ./03-webapp || exit 1
INDEX_PAGE_URL="$(terraform output -raw index_page_url)"
cd ..
echo "NOTE: Webapp index page URL: ${INDEX_PAGE_URL}"

# -----------------------------------------------------------------------------------------------
# Step 1: Discover Azure Function App endpoint
# -----------------------------------------------------------------------------------------------
echo "NOTE: Retrieving Azure Function App API endpoint..."

# Discover the Function App name created by Terraform
FunctionAppName=$(az functionapp list \
  --resource-group sb-keygen-rg \
  --query "[?starts_with(name, 'func-keygen-')].name" \
  --output tsv)

URL="https://$(az functionapp show \
  --name "$FunctionAppName" \
  --resource-group sb-keygen-rg \
  --query "defaultHostName" \
  -o tsv)/api"

export API_BASE="${URL}"
echo "NOTE: Function App endpoint - ${API_BASE}"

# -----------------------------------------------------------------------------------------------
# Step 2: Submit SSH key generation request
# -----------------------------------------------------------------------------------------------
KEY_TYPE="${KEY_TYPE:-rsa}"
KEY_BITS="${KEY_BITS:-2048}"

REQ_PAYLOAD=$(jq -n --arg kt "$KEY_TYPE" --arg kb "$KEY_BITS" \
  '{ key_type: $kt, key_bits: ($kb | tonumber) }')

echo "NOTE: Sending request - key_type=${KEY_TYPE}, key_bits=${KEY_BITS}"
RESPONSE=$(curl -s -X POST "${API_BASE}/keygen" \
  -H "Content-Type: application/json" \
  -d "$REQ_PAYLOAD")

REQUEST_ID=$(echo "$RESPONSE" | jq -r '.request_id // empty')

if [[ -z "$REQUEST_ID" ]]; then
  echo "ERROR: No request_id returned."
  echo "NOTE: Response was: $RESPONSE"
  exit 1
fi

echo "NOTE: Submitted keygen request (${REQUEST_ID})."
echo "NOTE: Polling for result..."

# -----------------------------------------------------------------------------------------------
# Step 3: Poll result endpoint until response available
# -----------------------------------------------------------------------------------------------
MAX_ATTEMPTS=30
SLEEP_SECONDS=2

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  RESULT=$(curl -s "${API_BASE}/result/${REQUEST_ID}")
  STATUS=$(echo "$RESULT" | jq -r '.status // empty')

  if [[ "$STATUS" == "complete" ]]; then
    echo "NOTE: Key generation complete."
    #echo "$RESULT" | jq
    exit 0
  fi

  if [[ "$STATUS" == "error" ]]; then
    echo "ERROR: Service reported an error."
    echo "$RESULT" | jq
    exit 1
  fi

  echo "WARNING: Attempt ${i}/${MAX_ATTEMPTS}: pending..."
  sleep "$SLEEP_SECONDS"
done

echo "ERROR: Key generation did not complete after ${MAX_ATTEMPTS} attempts."
exit 1
