variable "project_name" {
  description = "Name of the project, used as a prefix for all resources"
  type        = string
  default     = "movieapp"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "East US 2"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}