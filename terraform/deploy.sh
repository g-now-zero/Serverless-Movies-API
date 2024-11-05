#!/bin/bash
set -e  # Exit on any error

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print status messages
status() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

error() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# Function to check if a command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1 successful${NC}"
    else
        error "$1 failed"
    fi
}

status "Starting Deployment Process"

# Check if user is logged into Azure CLI
echo "Checking Azure CLI login status..."
if ! az account show >/dev/null 2>&1; then
    warning "Not logged in to Azure CLI. Initiating login..."
    if ! az login; then
        error "Azure login failed"
    fi
fi
status "Azure CLI login verified"

# Get current Azure subscription
CURRENT_SUB=$(az account show --query name -o tsv)
echo "Current subscription: $CURRENT_SUB"
read -p "Continue with this subscription? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please select the subscription you want to use:"
    az account list --query "[].{Name:name, SubscriptionId:id}" -o table
    read -p "Enter the Subscription ID you want to use: " SUB_ID
    az account set --subscription $SUB_ID
    echo "✓ Subscription set to: $(az account show --query name -o tsv)"
fi

# Ask for OMDB API Key if not set
if [ -z "$OMDB_API_KEY" ]; then
    read -p "Please enter your OMDB API Key (get one at http://www.omdbapi.com/apikey.aspx): " OMDB_API_KEY
    if [ -z "$OMDB_API_KEY" ]; then
        error "No OMDB API Key provided"
    fi
fi
export OMDB_API_KEY

status "Initializing Terraform"
terraform init
check_status "Terraform initialization"

status "Applying Terraform Configuration"
terraform apply -auto-approve
check_status "Terraform apply"

# Export necessary environment variables
status "Exporting Environment Variables"
export COSMOSDB_CONNECTION_STRING=$(terraform output -raw cosmos_db_connection_string)
export STORAGE_CONNECTION_STRING=$(terraform output -raw primary_storage_connection_string)
export OPENAI_API_ENDPOINT=$(terraform output -raw openai_endpoint)
export OPENAI_API_KEY=$(terraform output -raw openai_api_key)
export OPENAI_DEPLOYMENT_NAME=$(terraform output -raw openai_deployment_name)
export APIM_GATEWAY_URL=$(terraform output -raw api_management_gateway_url)

# Print confirmation of exports (without showing sensitive values)
echo "Environment variables exported:"
echo "- Cosmos DB connection string: [secured]"
echo "- Storage connection string: [secured]"
echo "- OpenAI endpoint: $OPENAI_API_ENDPOINT"
echo "- OpenAI deployment name: $OPENAI_DEPLOYMENT_NAME"
echo "- API Management Gateway URL: $APIM_GATEWAY_URL"

status "Publishing Azure Function App"
cd ../movie-api
func azure functionapp publish movieapp-dev-func
check_status "Function App deployment"

cd ../scripts

status "Starting Data Seeding Process"
python seed_data.py
check_status "Data seeding"

status "Starting Cover Image Upload Process"
python upload_covers.py
check_status "Cover image upload"

cd ../terraform

status "Waiting for API Management to be Ready"
echo "This may take several minutes..."
APIM_NAME="movieapp-dev-apim"
END=$((SECONDS + 300)) # 5 minute timeout

while [ $SECONDS -lt $END ]; do
    STATUS=$(az apim show --name $APIM_NAME --resource-group movieapp-dev-rg --query "properties.provisioningState" -o tsv 2>/dev/null)
    if [ "$STATUS" = "Succeeded" ]; then
        echo -e "${GREEN}✓ API Management is ready!${NC}"
        break
    fi
    echo "Current status: $STATUS"
    sleep 30
done

if [ $SECONDS -ge $END ]; then
    warning "Timeout waiting for APIM to be ready. Proceeding with tests anyway..."
fi

status "Testing API Endpoints"
FUNCTION_APP_NAME="movieapp-dev-func"

# Remove any extra https:// from the URL
APIM_GATEWAY_URL=$(echo "${APIM_GATEWAY_URL}" | sed 's|https://https://|https://|')

# Test each endpoint and store results
echo "Testing getmovies endpoint..."
GETMOVIES_TEST=$(curl -s -o /dev/null -w "%{http_code}" "${APIM_GATEWAY_URL}/api/getmovies")
if [ "$GETMOVIES_TEST" = "200" ]; then
    echo -e "${GREEN}✓ getmovies endpoint is accessible${NC}"
else
    warning "getmovies endpoint returned status $GETMOVIES_TEST"
fi

echo "Testing getmoviesbyyear endpoint..."
GETBYYEAR_TEST=$(curl -s -o /dev/null -w "%{http_code}" "${APIM_GATEWAY_URL}/api/getmoviesbyyear?year=2008")
if [ "$GETBYYEAR_TEST" = "200" ]; then
    echo -e "${GREEN}✓ getmoviesbyyear endpoint is accessible${NC}"
else
    warning "getmoviesbyyear endpoint returned status $GETBYYEAR_TEST"
fi

echo "Testing getmoviesummary endpoint..."
GETSUMMARY_TEST=$(curl -s -o /dev/null -w "%{http_code}" "${APIM_GATEWAY_URL}/api/getmoviesummary?title=WALL-E")
if [ "$GETSUMMARY_TEST" = "200" ]; then
    echo -e "${GREEN}✓ getmoviesummary endpoint is accessible${NC}"
else
    warning "getmoviesummary endpoint returned status $GETSUMMARY_TEST"
fi

status "Deployment Summary"
echo "Your API is now available at: ${APIM_GATEWAY_URL}"
echo "API Management portal will be available at: https://${FUNCTION_APP_NAME}-apim.developer.azure-api.net"
echo -e "\nEndpoint Status:"
echo "- getmovies: $GETMOVIES_TEST"
echo "- getmoviesbyyear: $GETBYYEAR_TEST"
echo "- getmoviesummary: $GETSUMMARY_TEST"

if [ "$GETMOVIES_TEST" = "200" ] && [ "$GETBYYEAR_TEST" = "200" ] && [ "$GETSUMMARY_TEST" = "200" ]; then
    echo -e "\n${GREEN}✓ Deployment completed successfully!${NC}"
else
    warning "Deployment completed with warnings. Please check the endpoint status above."
fi