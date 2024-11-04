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

# In main.tf

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

# Azure OpenAI Model Deployment
resource "azurerm_cognitive_deployment" "gpt35" {
  name                 = "gpt-35-turbo-16k"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo-16k"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 1
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
    FUNCTIONS_WORKER_RUNTIME       = "python"
    COSMOSDB_CONNECTION_STRING     = azurerm_cosmosdb_account.main.primary_sql_connection_string
    STORAGE_CONNECTION_STRING      = azurerm_storage_account.main.primary_connection_string
    OPENAI_API_ENDPOINT           = azurerm_cognitive_account.openai.endpoint
    OPENAI_API_KEY                = azurerm_cognitive_account.openai.primary_access_key
    OPENAI_DEPLOYMENT_NAME        = azurerm_cognitive_deployment.gpt35.name
    OPENAI_API_VERSION           = "2024-08-01-preview"
    EnableWorkerIndexing          = "true"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Management Service
resource "azurerm_api_management" "main" {
  name                = "${var.project_name}-${var.environment}-apim"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "Movie API Publisher"
  publisher_email     = "admin@movieapi.com"
  sku_name           = "Consumption_0"  # Using consumption tier for serverless

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Management API
resource "azurerm_api_management_api" "movies" {
  name                = "movies-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision           = "1"
  display_name       = "Movies API"
  path               = "api"
  protocols          = ["https"]
  service_url        = "https://${azurerm_linux_function_app.main.default_hostname}"

  import {
    content_format = "openapi"
    content_value  = <<EOF
openapi: 3.0.0
info:
  title: Movies API
  version: '1.0'
paths:
  /api/getmovies:
    get:
      summary: Get all movies
      operationId: getAllMovies
      responses:
        '200':
          description: List of all movies
  /api/getmoviesbyyear:
    get:
      summary: Get movies by year
      operationId: getMoviesByYear
      parameters:
        - name: year
          in: query
          required: true
          schema:
            type: integer
      responses:
        '200':
          description: List of movies for specified year
  /api/getmoviesummary:
    get:
      summary: Get AI-generated movie summary
      operationId: getMovieSummary
      parameters:
        - name: title
          in: query
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Movie summary
EOF
  }
}

# Rate limiting policy
resource "azurerm_api_management_api_policy" "rate_limit" {
  api_name            = azurerm_api_management_api.movies.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rate-limit calls="10" renewal-period="60" />
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
</policies>
XML
}