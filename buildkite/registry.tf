# Buildkite Packages OCI registry. team_ids is required and immutable after
# creation, so the registry gets its own team.
resource "buildkite_team" "registry" {
  name                = var.registry_name
  privacy             = "SECRET"
  default_team        = false
  default_member_role = "MEMBER"
}

locals {
  # Pipelines allowed to push, via OIDC. Add new projects here.
  pushers = [buildkite_pipeline.performance, buildkite_pipeline.cooking]

  # One statement per pipeline.
  oidc_policy = yamlencode([
    for p in local.pushers : {
      iss    = "https://agent.buildkite.com"
      scopes = ["read_packages", "write_packages"]
      claims = { pipeline_slug = { equals = p.slug } }
    }
  ])
}

# Layout: one registry per image kind, one image per repo inside it.
#   manifests/<repo>   k8s manifests artifact that Flux pulls (webhook below)
#   images/<repo>      app images (<repo>-<component> if a repo has several)
# Push from the pipelines' jobs via OIDC
# (`buildkite-agent oidc request-token --audience https://packages.buildkite.com/<org>/<registry>`,
# username "buildkite"). Cluster pulls use a static read token instead,
# see kubernetes/apps/buildkite/secret-registry-pull.sops.yaml.example.
moved {
  from = buildkite_registry.oci
  to   = buildkite_registry.manifests
}

resource "buildkite_registry" "manifests" {
  name        = var.manifests_registry_name
  ecosystem   = "oci"
  description = "K8s manifests artifacts that Flux pulls, one image per repo"
  emoji       = ":kubernetes:"
  team_ids    = [buildkite_team.registry.uuid]
  oidc_policy = local.oidc_policy
}

resource "buildkite_registry" "images" {
  name        = var.images_registry_name
  ecosystem   = "oci"
  description = "App images built by the pipelines, one image per repo"
  emoji       = ":docker:"
  team_ids    = [buildkite_team.registry.uuid]
  oidc_policy = local.oidc_policy
}

# MANUAL: the manifests registry's `package.created` webhook is not managed here. The
# provider and the Buildkite API have no registry webhook support. In the UI
# (registry > Settings > Notification Services > Webhook) set the URL to
# https://flux-webhook.<domain><Receiver buildkite-registry status.webhookPath>,
# set the token to BUILDKITE_WEBHOOK_TOKEN from kubernetes/components/sops/cluster-secrets.sops.yaml (sent as X-Buildkite-Token, checked by the gateway route), and select `package.created`. Flux side:
# kubernetes/apps/flux-system/flux-instance/app/receiver-buildkite.yaml.

# Canary SUT images. Separate from the Flux artifact registry so an image push
# does not fire that registry's package.created webhook.
resource "buildkite_registry" "sut" {
  name        = "performancesut"
  ecosystem   = "oci"
  description = "Canary SUT images built by the performance pipeline"
  emoji       = ":docker:"
  team_ids    = [buildkite_team.registry.uuid]

  oidc_policy = yamlencode([{
    iss    = "https://agent.buildkite.com"
    scopes = ["read_packages", "write_packages"]
    claims = { pipeline_slug = { equals = buildkite_pipeline.performance.slug } }
  }])
}
