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

# Same manual Entire link and `tofu import buildkite_pipeline.cooking <graphql-id>`
# as above. Steps live in the cooking repo (.buildkite/pipeline.yml).
resource "buildkite_pipeline" "cooking" {
  name           = "cooking"
  description    = "Dagger CI for the Entire-hosted cooking repo"
  repository     = var.cooking_repo_url
  default_branch = "main"
  cluster_id     = buildkite_cluster.sailing.id

  steps = yamlencode({
    steps = [{
      label   = ":pipeline: Pipeline Upload"
      command = "buildkite-agent pipeline upload"
    }]
  })
}
