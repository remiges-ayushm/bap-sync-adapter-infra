# bap-sync-adapter-infra

Terraform for a Beckn ONIX BAP↔BPP sandbox network on GCP: 4 Cloud Run services, a private Memorystore Redis cache, and the supporting VPC/IAM/Workload-Identity plumbing needed to deploy them.

## Architecture

| Service | Purpose | Image | Port | Config |
|---|---|---|---|---|
| `bap-sync-adapter` | Sync/async adapter sitting in front of `onix-bap` | `ayushmatha2001/bap-sync-adapter:v1` — built from a dedicated repo | — | `REDIS_URL`, `ONIX_URL`, `APP_ENV` env vars |
| `sandbox-bpp` | Mock BPP fixtures server used by `onix-bpp` | `ayushmatha2001/test-repo:v2` — built from a dedicated repo | 3002 | `RESPONSE_FIXTURES_BASE_URL` env var |
| `onix-bap` | ONIX BAP protocol adapter | `fidedocker/onix-adapter` — shared public image, behavior set entirely by mounted config | 8081 | Secret Manager volumes built from [`terraform/onix-bap-config/`](terraform/onix-bap-config/) |
| `onix-bpp` | ONIX BPP protocol adapter | `fidedocker/onix-adapter` — same shared image as `onix-bap` | 8082 | Secret Manager volumes built from [`terraform/onix-bpp-config/`](terraform/onix-bpp-config/) |

Both ONIX adapters read/write through the same Redis instance over a Serverless VPC Access connector (`run-to-redis`), and each ONIX adapter's routing config is templated with the Cloud Run URL of the service it forwards to (`onix-bap` → `bap-sync-adapter`, `onix-bpp` → `sandbox-bpp`).

Only `onix-bap` and `onix-bpp` share a single public image and need no build step. `bap-sync-adapter` and `sandbox-bpp` each come from their own source repo and Docker Hub image — see below.

## Source repositories for the custom images

| Cloud Run service | Source repo | Current image |
|---|---|---|
| `bap-sync-adapter` | https://github.com/remiges-ayushm/BAP-sync-adapter | `ayushmatha2001/bap-sync-adapter:v1` |
| `sandbox-bpp` | https://github.com/remiges-ayushm/sandbox-go | `ayushmatha2001/test-repo:v2` |

You can either reuse the existing published images as-is (fastest way to get started — no build step needed), or clone one of the repos above, build it, and push your own image to Docker Hub:

```bash
git clone https://github.com/remiges-ayushm/BAP-sync-adapter
cd BAP-sync-adapter
docker build -t <your-dockerhub-user>/bap-sync-adapter:<tag> .
docker push <your-dockerhub-user>/bap-sync-adapter:<tag>
```

```bash
git clone https://github.com/remiges-ayushm/sandbox-go
cd sandbox-go
docker build -t <your-dockerhub-user>/sandbox-go:<tag> .
docker push <your-dockerhub-user>/sandbox-go:<tag>
```

If you push your own image, update the `image = "..."` line for that service in [`terraform/cloud-run-bap-sync-adapter.tf`](terraform/cloud-run-bap-sync-adapter.tf) or [`terraform/cloud-run-sandbox-bpp.tf`](terraform/cloud-run-sandbox-bpp.tf) accordingly. `onix-bap`/`onix-bpp` use the shared `fidedocker/onix-adapter` image and never need this change.

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install), authenticated with application default credentials: `gcloud auth application-default login`
- [Terraform](https://developer.hashicorp.com/terraform/install) (provider `hashicorp/google ~> 6.0`, declared in [`terraform/provider.tf`](terraform/provider.tf))
- A GCP project with billing enabled, and permissions to enable APIs and create service accounts/IAM bindings on it
- Docker, only if you intend to rebuild `bap-sync-adapter` or `sandbox-bpp` from source

Terraform state is local (no remote backend configured) — `*.tfstate` files are gitignored, so keep them somewhere safe if you're not the only person applying this.

## Configuring variables

Set these in [`terraform/terraform.tfvars`](terraform/terraform.tfvars) (see [`terraform/variables.tf`](terraform/variables.tf) for defaults):

| Variable | Required? | Notes |
|---|---|---|
| `project_id` | Yes, no default | Target GCP project |
| `region` | No (`asia-southeast1`) | Region for all resources |
| `repository_id` | No (`bap-sync-adapter-infra`) | Artifact Registry repo id (provisioned but unused by the Docker Hub images) |
| `github_repositories`, `github_wif_pool_id`, `github_wif_provider_id`, `github_deployer_service_account_id` | No | Only relevant if you wire up GitHub Actions to deploy via Workload Identity Federation |
| `onix_bap_url` | No (placeholder default) | See the two-pass apply below — must be set to the real `onix-bap` URL *after* the first apply |
| `response_fixtures_base_url` | No | Base URL `sandbox-bpp` serves fixture responses from |

## Deploying: the bap-sync-adapter ↔ onix-bap URL cycle

`bap-sync-adapter` and `onix-bap` each need the other's Cloud Run URL to talk to each other, but a true cycle can't be resolved by Terraform in a single pass, so the two directions are wired differently:

- **`onix-bap` → `bap-sync-adapter`** is a direct Terraform resource reference (`google_cloud_run_v2_service.bap_sync_adapter.uri`, in [`terraform/onix-bap.tf`](terraform/onix-bap.tf)). Terraform resolves this automatically in one `apply` — it creates `bap-sync-adapter` first, then bakes its real URL into `onix-bap`'s routing config.
- **`bap-sync-adapter` → `onix-bap`** is the `ONIX_URL` env var in [`terraform/cloud-run-bap-sync-adapter.tf`](terraform/cloud-run-bap-sync-adapter.tf), sourced from `var.onix_bap_url` — a plain input variable, defaulting to a placeholder. It can't be a direct resource reference the other way, because that would create an actual dependency cycle and Terraform would refuse to plan.

So the first deploy needs **two applies**:

1. `terraform init`
2. `terraform apply` — leave `onix_bap_url` unset (or at its placeholder default). This provisions Redis, the VPC connector, `bap-sync-adapter` (temporarily pointed at the placeholder), `sandbox-bpp`, `onix-bap` (already correctly wired to the real `bap-sync-adapter` URL), and `onix-bpp` (already correctly wired to the real `sandbox-bpp` URL).
3. `terraform output onix_bap_url` — grab the real Cloud Run URL for `onix-bap`.
4. Add `onix_bap_url = "<that URL>"` to `terraform.tfvars`.
5. `terraform apply` again — this only updates `bap-sync-adapter`'s `ONIX_URL` env var (a new Cloud Run revision); everything else is already correctly wired from step 2.
6. Check all outputs: `bap_sync_adapter_url`, `sandbox_bpp_url`, `onix_bap_url`, `onix_bpp_url`, `redis_host`/`redis_port`, `artifact_registry_repo_url`.

There's no equivalent cycle between `sandbox-bpp` and `onix-bpp` — `sandbox-bpp` doesn't take a URL variable pointing back at `onix-bpp`, so that pair is fully wired in a single apply.

## Security note: sandbox keys are hardcoded

The `keyManager` blocks in [`terraform/onix-bap-config/local-simple-bap.yaml.tftpl`](terraform/onix-bap-config/local-simple-bap.yaml.tftpl) (both the `bapTxnReceiver` and `bapTxnCaller` modules) and [`terraform/onix-bpp-config/local-simple-bpp.yaml.tftpl`](terraform/onix-bpp-config/local-simple-bpp.yaml.tftpl) (`bppTxnReceiver`/`bppTxnCaller`) contain hardcoded signing/encryption keys and `networkParticipant` IDs (`bap1.apexsb.iontest.in`, `bpp1.apexsb.iontest.in`) that only identify this demo network. These are static YAML values, not Terraform variables.

If you're standing this up as anything beyond a throwaway sandbox, hand-edit `keyId`, `signingPrivateKey`, `signingPublicKey`, `encrPrivateKey`, `encrPublicKey`, and `networkParticipant` in both files (all four occurrences — receiver and caller in each) before registering your own network participant identity.
