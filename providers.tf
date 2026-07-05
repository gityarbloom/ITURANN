terraform {
  required_version = ">= 1.0.0"
  backend "gcs" {
    bucket = "terraform-mafat-ai-gee-monitor-dev"
    prefix = "grafana-dashboards/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}