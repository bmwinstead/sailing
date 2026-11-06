resource "buildkite_cluster" "sailing" {
  name        = var.cluster_name
  description = "Self-hosted agents running on the sailing k8s cluster"
  emoji       = ":kubernetes:"
  color       = "#326ce5"
}

resource "buildkite_cluster_queue" "kubernetes" {
  cluster_id = buildkite_cluster.sailing.id
  key        = var.queue_key
}
