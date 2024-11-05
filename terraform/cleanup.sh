#!/bin/bash
set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will destroy all resources in the movieapp-dev-rg resource group${NC}"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 1
fi

echo -e "\n${GREEN}=== Starting Cleanup ===${NC}"

# Run terraform destroy
echo -e "\n${GREEN}=== Running Terraform Destroy ===${NC}"
terraform destroy -auto-approve

# Additional cleanup to be thorough
echo -e "\n${GREEN}=== Checking for Resource Group ===${NC}"
if az group show --name movieapp-dev-rg >/dev/null 2>&1; then
    echo "Resource group still exists, forcing deletion..."
    az group delete --name movieapp-dev-rg --yes --no-wait
    echo "Resource group deletion initiated"
fi

# Clean local state
echo -e "\n${GREEN}=== Cleaning Local State ===${NC}"
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/

echo -e "\n${GREEN}=== Cleanup Complete ===${NC}"
echo "You can now rebuild the container with:"
echo -e "${YELLOW}cd ..${NC}"
echo -e "${YELLOW}docker build . --no-cache -t serverless-movies-api${NC}"
echo -e "${YELLOW}docker run -it serverless-movies-api${NC}"