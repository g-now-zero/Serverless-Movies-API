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