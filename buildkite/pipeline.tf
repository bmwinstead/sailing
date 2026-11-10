# The pipeline must be linked to the Entire repository provider connection
# (Buildkite Settings > Repository Providers), which the provider can't set —
# create it in the UI by picking the repo from the connection, then
# `tofu import buildkite_pipeline.performance <graphql-id>`.
#
# Steps live in the performance repo (.buildkite/pipeline.yml). This resource
# only uploads them.
resource "buildkite_pipeline" "performance" {
  name           = "performance"
  description    = "Dagger CI for the Entire-hosted performance repo"
  repository     = var.performance_repo_url
  default_branch = "main"
  cluster_id     = buildkite_cluster.sailing.id

  steps = yamlencode({
    steps = [{
      label   = ":pipeline: Pipeline Upload"
      command = "buildkite-agent pipeline upload"
    }]
  })
}
