provider "google" {
  project = var.project_id
  region  = var.region
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  services = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "redis.googleapis.com",             # Memorystore itself
    "vpcaccess.googleapis.com",         # Serverless VPC Access connector
    "servicenetworking.googleapis.com", # the private-services VPC peering Memorystore requires
    "compute.googleapis.com",           # VPC networks/reserved IP ranges are Compute Engine resources under the hood
  ]
}

resource "google_project_service" "enabled_services" {
  for_each = toset(local.services)
  project  = var.project_id
  service  = each.key

  disable_on_destroy = false
}