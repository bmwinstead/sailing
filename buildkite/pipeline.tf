# The pipeline must be linked to the Entire repository provider connection
# (Buildkite Settings > Repository Providers), which the provider can't set —
# create it in the UI by picking the repo from the connection, then
# `tofu import buildkite_pipeline.performance <graphql-id>`.
#
# This pipeline holds no repo logic. Its one step uploads .buildkite/pipeline.yml
# from the performance repo. Cluster settings that repo steps need come from
# the pipeline env below.
resource "buildkite_pipeline" "performance" {
  name           = "performance"
  description    = "Dagger CI for the Entire-hosted performance repo"
  repository     = var.performance_repo_url
  default_branch = "main"
  cluster_id     = buildkite_cluster.sailing.id

  steps = yamlencode({
    env = {
      DAGGER_VERSION     = var.dagger_version
      DAGGER_ENGINE_HOST = "tcp://dagger-engine.buildkite.svc.cluster.local:1234"
    }
    steps = [{
      label  = ":pipeline: upload"
      agents = { queue = buildkite_cluster_queue.kubernetes.key }
      # The repo's steps use $VAR at run time, so skip upload-time interpolation.
      commands = ["buildkite-agent pipeline upload --no-interpolation"]
      plugins = [
        "entire",
        {
          kubernetes = {
            podSpec = {
              # Needs bash, curl, git, GNU coreutils (entire plugin requirements).
              containers = [{ image = "ghcr.io/buildkite/agent:4.7.0-ubuntu-24.04" }]
            }
          }
        },
      ]
    }]
  })
}
