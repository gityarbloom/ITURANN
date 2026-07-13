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

resource "google_secret_manager_secret_version" "grafana_user_version" {
  secret      = google_secret_manager_secret.grafana_user_secret.id
  secret_data = var.grafana_admin_user
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
  source_ranges = concat(var.source_ranges, ["35.235.240.0/20"])
  target_tags   = ["grafana-node"]
}

# מאפשר גישת SSH ל-VM ללא IP חיצוני, דרך IAP (Identity-Aware Proxy) בלבד.
# נדרש לצורך דיבוג/תחזוקה של ה-VM כאשר אין לו External IP.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = var.network
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
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
    # access_config {} 
  }

  metadata = {
    startup-script = replace(<<-EOT
      #!/bin/bash

      echo "=== [STARTUP] Waiting for Network and Metadata Server... ==="
      # חסימת הריצה עד שהרשת תתייצב ושרת המטא-דאטה יענה (פותר את ה-Race Condition באתחול)
      until curl -s -I -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance" | grep -q "200 OK"; do
        sleep 3
      done
      echo "=== [STARTUP] Network is ready! Starting Grafana VM Setup ==="

      # 1. יצירת הקובץ בתיקיית tmp זמנית והעברתו לתיקיית דוקר המובנית של COS
      HOME=/tmp docker-credential-gcr configure-docker --registries=${var.region}-docker.pkg.dev
      mkdir -p /var/lib/docker
      cp /tmp/.docker/config.json /var/lib/docker/config.json

      # 2. שליפת הטוקן והסודות בעזרת Python
      TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

      if [ -z "$TOKEN" ]; then
        echo "ERROR: Failed to retrieve token from metadata server." >&2
        exit 1
      fi

      # עצירת הסקריפט במקרה של שגיאה בהמשך
      set -e

      GRAFANA_USER_BASE64=$(curl -s -f -H "Authorization: Bearer $TOKEN" "https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/grafana-admin-user/versions/latest:access" | python3 -c "import sys, json; print(json.load(sys.stdin)['payload']['data'])")
      GRAFANA_USER=$(echo "$GRAFANA_USER_BASE64" | base64 -d)

      GRAFANA_PASSWORD_BASE64=$(curl -s -f -H "Authorization: Bearer $TOKEN" "https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/grafana-admin-password/versions/latest:access" | python3 -c "import sys, json; print(json.load(sys.stdin)['payload']['data'])")
      GRAFANA_PASSWORD=$(echo "$GRAFANA_PASSWORD_BASE64" | base64 -d)

      # =========================================================
      # 3. Mount production dashboards from GCS sync path
      # =========================================================
      echo "=== [STARTUP] Creating local dashboards cache directory... ==="
      mkdir -p /var/lib/docker/dashboards
      chmod 777 /var/lib/docker/dashboards

      echo "=== [STARTUP] Starting Grafana container with synced dashboards volume... ==="
      docker --config /var/lib/docker run -d -p 3000:3000 --name grafana-app --restart always \
        -e "GF_SECURITY_ADMIN_USER=$GRAFANA_USER" \
        -e "GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD" \
        -e "GRAFANA_DASHBOARDS_BUCKET=${google_storage_bucket.grafana_dashboards_bucket.name}" \
        -e "GRAFANA_DASHBOARDS_PATH=/var/lib/grafana/dashboards" \
        -v /var/lib/docker/dashboards:/var/lib/grafana/dashboards \
        ${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_name}/${var.image_name}:1.0.0-dev

      echo "=== [STARTUP] Grafana setup completed successfully ==="
    EOT
    , "\r", "")
  }
  service_account {
    email  = google_service_account.grafana_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_storage_bucket.grafana_dashboards_bucket,
    google_storage_bucket_iam_member.bucket_reader,
    google_project_iam_member.ar_reader,
    google_project_iam_member.logging_reader,
    google_secret_manager_secret_version.grafana_user_version,
    google_secret_manager_secret_version.grafana_password_version,
    google_secret_manager_secret_iam_member.user_secret_accessor,
    google_secret_manager_secret_iam_member.password_secret_accessor
  ]
}
