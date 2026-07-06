variable "project_id" {
  type    = string
  default = "mafat-ai-gee-monitor-dev"
}

variable "grafana_admin_user" {
  type        = string
  description = "The admin username for Grafana (will be saved in Secret Manager)"
}

variable "grafana_initial_password" {
  type        = string
  description = "The admin password for Grafana (will be saved in Secret Manager)"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-a"
}

variable "network" {
  type    = string
  default = "default"
}

variable "source_ranges" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "repository_name" {
  type    = string
  default = "early-warning--monitoring"
}

variable "image_name" {
  type    = string
  default = "grafana"
}