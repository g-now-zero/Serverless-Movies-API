output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "cosmos_db_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "primary_storage_connection_string" {
  value     = azurerm_storage_account.main.primary_connection_string
  sensitive = true
}

output "cosmos_db_connection_string" {
  value     = azurerm_cosmosdb_account.main.primary_sql_connection_string
  sensitive = true
}

output "openai_endpoint" {
  value = module.openai.openai_endpoint
}

output "openai_api_key" {
  value     = module.openai.openai_primary_key
  sensitive = true
}

output "openai_deployment_name" {
  value = "gpt-35-turbo-16k" 
}

output "api_management_gateway_url" {
  value = "https://${azurerm_api_management.main.gateway_url}"
}

output "apim_gateway_url" {
  value = "https://${azurerm_api_management.main.gateway_url}"
  description = "Gateway URL for the API Management service"
}

output "api_base_url" {
  value = "https://${azurerm_api_management.main.gateway_url}/api"
  description = "Base URL for API endpoints"
}