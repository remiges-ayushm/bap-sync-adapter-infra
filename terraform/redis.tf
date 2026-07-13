resource "google_compute_global_address" "private_ip_alloc" {
  name          = "google-managed-services-default"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "projects/${var.project_id}/global/networks/default"
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/default"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

resource "google_redis_instance" "cache" {
  name               = "ion-sandbox-redis"
  tier               = "BASIC"
  memory_size_gb     = 1
  region             = var.region
  authorized_network = "projects/${var.project_id}/global/networks/default"
  redis_version      = "REDIS_7_0"
  auth_enabled       = false
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

output "redis_host" {
  value = google_redis_instance.cache.host
}
output "redis_port" {
  value = google_redis_instance.cache.port
}

resource "google_vpc_access_connector" "connector" {
  name          = "run-to-redis"
  region        = var.region
  network       = "default"
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 3

  depends_on = [google_project_service.enabled_services]
}

output "vpc_connector_id" {
  value = google_vpc_access_connector.connector.id
}