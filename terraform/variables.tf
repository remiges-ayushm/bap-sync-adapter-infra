variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources in"
  type        = string
  default     = "asia-southeast1"
}

variable "repository_id" {
  description = "Artifact Registry repository ID"
  type        = string
  default     = "bap-sync-adapter-infra"
}

variable "github_repositories" {
  description = "GitHub repositories allowed to use the deployer workload identity"
  type        = list(string)
  default     = ["remiges-ayushm/bap-sync-adapter-infra"]
}

variable "github_wif_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions"
  type        = string
  default     = "github-actions"
}

variable "github_wif_provider_id" {
  description = "Workload Identity Provider ID for GitHub Actions"
  type        = string
  default     = "github-actions-provider"
}

variable "github_deployer_service_account_id" {
  description = "Service account ID used by GitHub Actions deploy workflow"
  type        = string
  default     = "github-deployer"
}