# The pipeline must be linked to the Entire repository provider connection
# (Buildkite Settings > Repository Providers), which the provider can't set —
# create it in the UI by picking the repo from the connection, then
# `tofu import buildkite_pipeline.performance <graphql-id>`.
#
# Step logic lives in performance-step.sh. Buildkite interpolates $VAR in
# pipeline settings, so every $ is doubled to reach the pod untouched.
resource "buildkite_pipeline" "performance" {
  name           = "performance"
  description    = "Dagger CI for the Entire-hosted performance repo"
  repository     = var.performance_repo_url
  default_branch = "main"
  cluster_id     = buildkite_cluster.sailing.id

  steps = yamlencode({
    steps = [{
      label    = ":dagger: dagger check"
      key      = "check"
      agents   = { queue = buildkite_cluster_queue.kubernetes.key }
      commands = [replace(file("${path.module}/performance-step.sh"), "$", "$$")]
      env = {
        DAGGER_VERSION     = var.dagger_version
        DAGGER_ENGINE_HOST = "tcp://dagger-engine.buildkite.svc.cluster.local:1234"
      }
      plugins = [
        "entire",
        {
          kubernetes = {
            podSpec = {
              # Needs bash, curl, git, GNU coreutils (entire plugin requirements).
              containers = [{ image = "debian:bookworm-slim" }]
            }
          }
        },
      ]
    }]
  })
}
