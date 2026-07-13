resource "google_cloud_run_v2_service" "bap_sync_adapter" {
  name     = "bap-sync-adapter"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
    containers {
      image = "ayushmatha2001/bap-sync-adapter:v1"
      env {
        name  = "REDIS_URL"
        value = "${google_redis_instance.cache.host}:${google_redis_instance.cache.port}"
      }
      env {
        name  = "ONIX_URL"
        value = var.onix_bap_url
      }
      env {
        name  = "APP_ENV"
        value = "production"
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "bap_sync_adapter_public" {
  location = google_cloud_run_v2_service.bap_sync_adapter.location
  name     = google_cloud_run_v2_service.bap_sync_adapter.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "bap_sync_adapter_url" {
  value = google_cloud_run_v2_service.bap_sync_adapter.uri
}