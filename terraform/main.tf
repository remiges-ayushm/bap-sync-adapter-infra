resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for ion-sandbox-infra"
  format        = "DOCKER"

  depends_on = [google_project_service.enabled_services]
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  cloud_build_runner_member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_service_account" "github_deployer" {
  account_id   = var.github_deployer_service_account_id
  display_name = "GitHub Actions deployer"
}

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = var.github_wif_pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC identity pool for GitHub Actions workflows"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_wif_provider_id
  display_name                       = "GitHub Actions provider"
  description                        = "Accept GitHub Actions OIDC tokens for allowed repositories"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.ref"              = "assertion.ref"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = join(" || ", [for repository in var.github_repositories : "assertion.repository == \"${repository}\""])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_actions_wif_user" {
  for_each = toset(var.github_repositories)

  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${each.value}"
}

resource "google_service_account_iam_member" "github_deployer_cloudbuild_runner_sa_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_deployer_cloudbuild_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_deployer_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_deployer_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.repoAdmin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_deployer_service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "github_deployer_cloudbuild_source_uploader" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "cloud_build_source_reader" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = local.cloud_build_runner_member
}

resource "google_project_iam_member" "cloud_build_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.cloud_build_runner_member
}

output "github_deployer_service_account_email" {
  value = google_service_account.github_deployer.email
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_actions.name
}

output "artifact_registry_repo_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}