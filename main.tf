resource "google_storage_bucket" "grafana_dashboards_bucket" {
  name                        = "${var.project_id}-grafana-dashboards"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false 
  uniform_bucket_level_access = true
}

resource "google_secret_manager_secret" "grafana_user_secret" {
  secret_id = "grafana-admin-user"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "grafana_password_secret" {
  secret_id = "grafana-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "grafana_password_version" {
  secret      = google_secret_manager_secret.grafana_password_secret.id
  secret_data = var.grafana_initial_password
}

resource "google_service_account" "grafana_sa" {
  account_id   = "grafana-vm-sa"
  display_name = "Service Account for Grafana VM"
}

resource "google_secret_manager_secret_iam_member" "user_secret_accessor" {
  secret_id = google_secret_manager_secret.grafana_user_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.grafana_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "password_secret_accessor" {
  secret_id = google_secret_manager_secret.grafana_password_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.grafana_sa.email}"
}

resource "google_storage_bucket_iam_member" "bucket_reader" {
  bucket = google_storage_bucket.grafana_dashboards_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.grafana_sa.email}"
}

resource "google_project_iam_member" "ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.grafana_sa.email}"
}

resource "google_project_iam_member" "logging_reader" {
  project = var.project_id
  role    = "roles/logging.viewer" 
  member  = "serviceAccount:${google_service_account.grafana_sa.email}"
}

resource "google_compute_firewall" "allow_grafana" {
  name    = "allow-grafana-port"
  network = var.network
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  source_ranges = var.source_ranges
  target_tags   = ["grafana-node"]
}

resource "google_compute_instance" "grafana_vm" {
  name         = "grafana-pipeline-dashboard"
  machine_type = var.machine_type
  tags         = ["grafana-node"]
  zone         = var.zone
  
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = var.network
    access_config {} 
  }

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      
      # התחברות לארטיפקט רגיסטרי האזורי
      docker login -u oauth2access -p "$(gcloud auth print-access-token)" https://${var.art_region}-docker.pkg.dev
      
      GRAFANA_USER=$(gcloud secrets versions access latest --secret="grafana-admin-user")
      GRAFANA_PASSWORD=$(gcloud secrets versions access latest --secret="grafana-admin-password")
      
      docker run -d -p 3000:3000 \
        -e "GF_SECURITY_ADMIN_USER=\$GRAFANA_USER" \
        -e "GF_SECURITY_ADMIN_PASSWORD=\$GRAFANA_PASSWORD" \
        -e "GRAFANA_DASHBOARDS_BUCKET=${google_storage_bucket.grafana_dashboards_bucket.name}" \
        ${var.art_region}-docker.pkg.dev/${var.project_id}/${var.repository_name}/${var.image_name}:1.0.0-dev
    EOT
  }

  service_account {
    email  = google_service_account.grafana_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # 🛑 המכונה תוקם רק אחרי שהבאקט, הלוגים, וכל הרשאות הגישה מוכנים לחלוטין
  depends_on = [
    google_storage_bucket.grafana_dashboards_bucket,
    google_storage_bucket_iam_member.bucket_reader,
    google_project_iam_member.ar_reader,
    google_project_iam_member.logging_reader,
    google_secret_manager_secret_iam_member.user_secret_accessor,
    google_secret_manager_secret_iam_member.password_secret_accessor
  ]
}