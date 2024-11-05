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

# Azure OpenAI Service using the official module
module "openai" {
  source              = "Azure/openai/azurerm"
  version             = "0.1.3"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  account_name        = "${var.project_name}-${var.environment}-openai"
  sku_name            = "S0"
  public_network_access_enabled = true

  deployment = {
    "gpt-35-turbo" = {
      name          = "gpt-35-turbo-16k"
      model_format  = "OpenAI"
      model_name    = "gpt-35-turbo-16k"
      model_version = "0613"
      scale_type    = "Standard"
      capacity      = 1
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [
    azurerm_resource_group.main
  ]
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
    FUNCTIONS_WORKER_RUNTIME       = "python"
    COSMOSDB_CONNECTION_STRING     = azurerm_cosmosdb_account.main.primary_sql_connection_string
    STORAGE_CONNECTION_STRING      = azurerm_storage_account.main.primary_connection_string
    OPENAI_API_ENDPOINT           = module.openai.openai_endpoint
    OPENAI_API_KEY                = module.openai.openai_primary_key
    OPENAI_DEPLOYMENT_NAME        = "gpt-35-turbo-16k"  # This matches the name in our module deployment
    OPENAI_API_VERSION           = "2024-08-01-preview"
    EnableWorkerIndexing          = "true"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

data "azurerm_function_app_host_keys" "main" {
  name                = azurerm_linux_function_app.main.name
  resource_group_name = azurerm_resource_group.main.name
  depends_on = [azurerm_linux_function_app.main]
}

# API Management Service
resource "azurerm_api_management" "main" {
  name                = "${var.project_name}-${var.environment}-apim"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "Movie API Publisher"
  publisher_email     = "admin@movieapi.com"
  sku_name           = "Consumption_0"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Store function key as a named value
resource "azurerm_api_management_named_value" "function_key" {
  name                = "function-key"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "function-key"
  value              = data.azurerm_function_app_host_keys.main.default_function_key
  secret             = true

  lifecycle {
    create_before_destroy = false
  }
}

# API Configuration
resource "azurerm_api_management_api" "movies" {
  name                = "movies-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision           = "1"
  display_name       = "Movies API"
  path               = "api"  # Adding path to match Function App
  protocols          = ["https"]
  service_url        = "https://${azurerm_linux_function_app.main.default_hostname}"
  subscription_required = false
}

# API Policy with corrected base-url
resource "azurerm_api_management_api_policy" "movies" {
  api_name            = azurerm_api_management_api.movies.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-backend-service base-url="https://${azurerm_linux_function_app.main.default_hostname}/api" />
    <set-query-parameter name="code" exists-action="override">
      <value>{{function-key}}</value>
    </set-query-parameter>
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <forward-request />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Operations
resource "azurerm_api_management_api_operation" "get_movies" {
  operation_id        = "get-movies"
  api_name           = azurerm_api_management_api.movies.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name       = "Get Movies"
  method             = "GET"
  url_template       = "/getmovies"
  description        = "Get all movies"
}

resource "azurerm_api_management_api_operation" "get_movies_by_year" {
  operation_id        = "get-movies-by-year"
  api_name           = azurerm_api_management_api.movies.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name       = "Get Movies by Year"
  method             = "GET"
  url_template       = "/getmoviesbyyear"
  description        = "Get movies by year"

  request {
    query_parameter {
      name          = "year"
      type          = "number"
      required      = true
      description   = "Year to filter movies"
    }
  }
}

resource "azurerm_api_management_api_operation" "get_movie_summary" {
  operation_id        = "get-movie-summary"
  api_name           = azurerm_api_management_api.movies.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name       = "Get Movie Summary"
  method             = "GET"
  url_template       = "/getmoviesummary"
  description        = "Get AI-generated movie summary"

  request {
    query_parameter {
      name          = "title"
      type          = "string"
      required      = true
      description   = "Movie title"
    }
  }
}