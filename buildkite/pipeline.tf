# Pipelines are created by hand in the UI (the API cannot link the Entire repo)
# and adopted here with an import block. To add a project: create the pipeline
# in the UI, then copy the `cooking` resource and import block below.
#
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

import {
  to = buildkite_pipeline.cooking
  id = "UGlwZWxpbmUtLS0wMWExZDVkMS1hNzcyLTQ2OTgtOWM2Yy02ZWYwZGZkZjZhMjc="
}

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
