resource "google_secret_manager_secret" "onix_bpp_main_config" {
  secret_id = "onix-bpp-main-config"
  replication {
    auto {}
  }
}
resource "google_secret_manager_secret_version" "onix_bpp_main_config" {
  secret = google_secret_manager_secret.onix_bpp_main_config.id
  secret_data = templatefile("${path.module}/onix-bpp-config/local-simple-bpp.yaml.tftpl", {
    redis_host = google_redis_instance.cache.host
    redis_port = google_redis_instance.cache.port
  })
}

resource "google_secret_manager_secret" "onix_bpp_receiver_routing" {
  secret_id = "onix-bpp-receiver-routing"
  replication {
    auto {}
  }
}
resource "google_secret_manager_secret_version" "onix_bpp_receiver_routing" {
  secret = google_secret_manager_secret.onix_bpp_receiver_routing.id
  secret_data = templatefile("${path.module}/onix-bpp-config/local-simple-routing-BPPReceiver.yaml.tftpl", {
    sandbox_bpp_url = google_cloud_run_v2_service.sandbox_bpp.uri
  })
}

resource "google_secret_manager_secret" "onix_bpp_caller_routing" {
  secret_id = "onix-bpp-caller-routing"
  replication {
    auto {}
  }
}
resource "google_secret_manager_secret_version" "onix_bpp_caller_routing" {
  secret      = google_secret_manager_secret.onix_bpp_caller_routing.id
  secret_data = file("${path.module}/onix-bpp-config/local-simple-routing-BPPCaller.yaml")
}

resource "google_secret_manager_secret" "onix_bpp_audit_fields" {
  secret_id = "onix-bpp-audit-fields"
  replication {
    auto {}
  }
}
resource "google_secret_manager_secret_version" "onix_bpp_audit_fields" {
  secret      = google_secret_manager_secret.onix_bpp_audit_fields.id
  secret_data = file("${path.module}/onix-bpp-config/audit-fields.yaml")
}

resource "google_cloud_run_v2_service" "onix_bpp" {
  name     = "onix-bpp"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
    containers {
      image = "fidedocker/onix-adapter"
      args  = ["./server", "--config=/app/config/local-simple-bpp.yaml"]
      ports {
        container_port = 8082
      } # matches http.port: 8082 in the YAML
      volume_mounts {
        name       = "main-config"
        mount_path = "/app/config"
      }
      volume_mounts {
        name       = "receiver-routing"
        mount_path = "/app/config/routing-receiver"
      }
      volume_mounts {
        name       = "caller-routing"
        mount_path = "/app/config/routing-caller"
      }
      volume_mounts {
        name       = "audit-fields"
        mount_path = "/app/config/audit"
      }
    }
    volumes {
      name = "main-config"
      secret {
        secret = google_secret_manager_secret.onix_bpp_main_config.secret_id
        items {
          version = google_secret_manager_secret_version.onix_bpp_main_config.version
          path    = "local-simple-bpp.yaml"
        }
      }
    }
    volumes {
      name = "receiver-routing"
      secret {
        secret = google_secret_manager_secret.onix_bpp_receiver_routing.secret_id
        items {
          version = google_secret_manager_secret_version.onix_bpp_receiver_routing.version
          path    = "local-simple-routing-BPPReceiver.yaml"
        }
      }
    }
    volumes {
      name = "caller-routing"
      secret {
        secret = google_secret_manager_secret.onix_bpp_caller_routing.secret_id
        items {
          version = google_secret_manager_secret_version.onix_bpp_caller_routing.version
          path    = "local-simple-routing-BPPCaller.yaml"
        }
      }
    }
    volumes {
      name = "audit-fields"
      secret {
        secret = google_secret_manager_secret.onix_bpp_audit_fields.secret_id
        items {
          version = "latest"
          path    = "audit-fields.yaml"
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "onix_bpp_public" {
  location = google_cloud_run_v2_service.onix_bpp.location
  name     = google_cloud_run_v2_service.onix_bpp.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "onix_bpp_url" {
  value = google_cloud_run_v2_service.onix_bpp.uri
}

resource "google_secret_manager_secret_iam_member" "onix_bpp_secrets_access" {
  for_each = toset([
    google_secret_manager_secret.onix_bpp_main_config.secret_id,
    google_secret_manager_secret.onix_bpp_receiver_routing.secret_id,
    google_secret_manager_secret.onix_bpp_caller_routing.secret_id,
    google_secret_manager_secret.onix_bpp_audit_fields.secret_id,
  ])
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}
