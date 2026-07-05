variable "project_id" {
  type    = string
  default = "mafat-ai-gee-monitor-dev"
}

variable "secret_name" {
  type    = string
  default = "grafana-admin-password"
}

variable "grafana_initial_password" {
  type        = string
  description = "The initial admin password for Grafana"

}

variable "region" {
  type    = string
  default = "me-west1"
}

variable "zone" {
  type    = string
  default = "me-west1-a"
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

variable "tags" {
  type    = list(string)
  default = ["grafana-node"]
}