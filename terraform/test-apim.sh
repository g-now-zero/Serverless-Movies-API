#!/bin/bash

APIM_NAME="movieapp-dev-apim"
APIM_URL="https://${APIM_NAME}.azure-api.net"

echo "Testing APIM endpoints..."
echo "APIM URL: $APIM_URL"

# Test getmovies endpoint
echo -e "\n=== Testing GET /api/getmovies ==="
curl -v "$APIM_URL/api/getmovies"

# Test getmoviesbyyear endpoint
echo -e "\n\n=== Testing GET /api/getmoviesbyyear?year=2008 ==="
curl -v "$APIM_URL/api/getmoviesbyyear?year=2008"

# Test getmoviesummary endpoint
echo -e "\n\n=== Testing GET /api/getmoviesummary?title=WALL-E ==="
curl -v "$APIM_URL/api/getmoviesummary?title=WALL-E"

# Additional diagnostic info
echo -e "\n\n=== APIM Details ==="
az apim show --name $APIM_NAME --resource-group movieapp-dev-rg \
    --query "{name:name, url:gatewayUrl, state:properties.provisioningState}" \
    -o table

echo -e "\n=== API Details ==="
az apim api list --resource-group movieapp-dev-rg --service-name $APIM_NAME \
    --query "[].{name:name, path:path, protocols:protocols}" \
    -o table