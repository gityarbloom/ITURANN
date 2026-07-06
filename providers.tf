terraform {
  required_version = ">= 1.0.0"

  # מושבת זמנית לטובת הבדיקות המקומיות שלכם
  # backend "gcs" {
  #   bucket = "terraform-mafat-ai-gee-monitor-dev"
  #   prefix = "grafana-dashboards/state"
  # }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39.0" # הגרסה המעודכנת שלכם
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}