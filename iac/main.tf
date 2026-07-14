terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

# ------------------------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "Short name prefix applied to all resources"
  type        = string
  default     = "multi-source-rag"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "centralus"
}

variable "sql_admin_username" {
  description = "Admin login for the Azure SQL logical server"
  type        = string
  default     = "sqladmin"
}

variable "openai_chat_model_name" {
  description = <<-EOT
    Azure OpenAI chat model name to deploy.
    NOTE: "GPT-5.2 Codex Global" (as requested) is not a model name/version pair
    that could be verified against the Azure OpenAI model catalog at the time this
    was written. Before applying, confirm the exact name + version available in
    var.location with: az cognitiveservices account list-models
    and update this value (and openai_chat_model_version below) accordingly.
  EOT
  type        = string
  default     = "gpt-5.2-codex"
}

variable "openai_chat_model_version" {
  description = "Version string for the chat model deployment (verify against model catalog)"
  type        = string
  default     = "global"
}

variable "openai_chat_deployment_capacity" {
  description = "Tokens-per-minute capacity (in thousands) for the chat model deployment"
  type        = number
  default     = 10
}

variable "openai_embedding_model_name" {
  description = "Azure OpenAI embedding model name to deploy"
  type        = string
  default     = "text-embedding-3-large"
}

variable "openai_embedding_model_version" {
  description = "Version string for the embedding model deployment"
  type        = string
  default     = "1"
}

variable "openai_embedding_deployment_capacity" {
  description = "Tokens-per-minute capacity (in thousands) for the embedding model deployment"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project = "multi-source-rag"
  }
}

# ------------------------------------------------------------------------------------------------
# Naming helper - Azure requires globally-unique names for storage, SQL, Search and Cognitive
# Services accounts, so a random suffix is appended to those.
# ------------------------------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "random_password" "sql_admin" {
  length      = 24
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

# ------------------------------------------------------------------------------------------------
# Resource group
# ------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ------------------------------------------------------------------------------------------------
# Blob storage
# ------------------------------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  name                     = "st${replace(var.prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ------------------------------------------------------------------------------------------------
# Azure AI Search (Basic tier)
# ------------------------------------------------------------------------------------------------

resource "azurerm_search_service" "this" {
  name                = "srch-${var.prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "basic"
  replica_count       = 1
  partition_count     = 1
  tags                = var.tags
}

# ------------------------------------------------------------------------------------------------
# Azure SQL - cheapest tier (Basic DTU, 5 DTU / 2GB)
# ------------------------------------------------------------------------------------------------

resource "azurerm_mssql_server" "this" {
  name                         = "sql-${var.prefix}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"
  tags                         = var.tags
}

resource "azurerm_mssql_database" "this" {
  name        = "sqldb-${var.prefix}"
  server_id   = azurerm_mssql_server.this.id
  sku_name    = "Basic"
  max_size_gb = 2
  tags        = var.tags
}

# ------------------------------------------------------------------------------------------------
# Azure OpenAI - chat + embedding deployments
# ------------------------------------------------------------------------------------------------

resource "azurerm_cognitive_account" "openai" {
  name                  = "oai-${var.prefix}-${random_string.suffix.result}"
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "oai-${var.prefix}-${random_string.suffix.result}"
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "chat" {
  name                 = "chat"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_chat_model_name
    version = var.openai_chat_model_version
  }

  sku {
    name     = "Standard"
    capacity = var.openai_chat_deployment_capacity
  }
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = "embedding"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.openai_embedding_model_name
    version = var.openai_embedding_model_version
  }

  sku {
    name     = "Standard"
    capacity = var.openai_embedding_deployment_capacity
  }
}

# ------------------------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------------------------

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "search_service_name" {
  value = azurerm_search_service.this.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "sql_admin_username" {
  value = var.sql_admin_username
}

output "sql_admin_password" {
  value     = random_password.sql_admin.result
  sensitive = true
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "openai_chat_deployment_name" {
  value = azurerm_cognitive_deployment.chat.name
}

output "openai_embedding_deployment_name" {
  value = azurerm_cognitive_deployment.embedding.name
}
