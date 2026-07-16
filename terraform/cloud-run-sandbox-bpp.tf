resource "google_cloud_run_v2_service" "sandbox_bpp" {
  name     = "sandbox-bpp"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  template {
    containers {
      image = "ayushmatha2001/test-repo:v2"
      ports { container_port = 3002 }
      env {
        name  = "RESPONSE_FIXTURES_BASE_URL"
        value = var.response_fixtures_base_url
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "sandbox_bpp_public" {
  location = google_cloud_run_v2_service.sandbox_bpp.location
  name     = google_cloud_run_v2_service.sandbox_bpp.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "sandbox_bpp_url" {
  value = google_cloud_run_v2_service.sandbox_bpp.uri
}