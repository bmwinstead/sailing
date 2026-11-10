# Buildkite Packages OCI registry. team_ids is required and immutable after
# creation, so the registry gets its own team.
resource "buildkite_team" "registry" {
  name                = var.registry_name
  privacy             = "SECRET"
  default_team        = false
  default_member_role = "MEMBER"
}

resource "buildkite_registry" "oci" {
  name        = var.registry_name
  ecosystem   = "oci"
  description = "OCI images built by the sailing pipelines"
  emoji       = ":docker:"
  team_ids    = [buildkite_team.registry.uuid]

  # Push from the performance pipeline's jobs only, via OIDC
  # (`buildkite-agent oidc request-token --audience https://packages.buildkite.com/<org>/<registry>`,
  # username "buildkite"). Cluster pulls use a static read token instead,
  # see kubernetes/apps/buildkite/secret-registry-pull.sops.yaml.example.
  oidc_policy = yamlencode([{
    iss    = "https://agent.buildkite.com"
    scopes = ["read_packages", "write_packages"]
    claims = { pipeline_slug = { equals = buildkite_pipeline.performance.slug } }
  }])
}

# MANUAL: the registry's `package.created` webhook is not managed here. The
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
