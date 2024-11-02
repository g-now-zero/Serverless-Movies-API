# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.location
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "${var.project_name}${var.environment}store"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version         = "TLS1_2"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Blob Container for movie images
resource "azurerm_storage_container" "images" {
  name                  = "movie-images"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "blob"
}

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.project_name}-${var.environment}-cosmos"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type         = "Standard"
  kind               = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cosmos DB Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "moviedb"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB Container
resource "azurerm_cosmosdb_sql_container" "movies" {
  name                = "movies"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = ["/year"]  
  
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }

    included_path {
      path = "/year/?"
    }

    included_path {
      path = "/alphabeticalGroups/*"
    }
  }
}

# App Service Plan for Functions
resource "azurerm_service_plan" "main" {
  name                = "${var.project_name}-${var.environment}-asp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type            = "Linux"
  sku_name           = "Y1" # Consumption plan for Functions

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = "${var.project_name}-${var.environment}-openai"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = "S0"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                       = "${var.project_name}-${var.environment}-func"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id           = azurerm_service_plan.main.id
  storage_account_name      = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
    COSMOSDB_CONNECTION_STRING = azurerm_cosmosdb_account.main.primary_sql_connection_string
    STORAGE_CONNECTION_STRING = azurerm_storage_account.main.primary_connection_string
    OPENAI_API_KEY = azurerm_cognitive_account.openai.primary_access_key
    OPENAI_API_ENDPOINT = azurerm_cognitive_account.openai.endpoint
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}