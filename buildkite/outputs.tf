output "cluster_id" {
  value = buildkite_cluster.sailing.id
}

output "queue_key" {
  value = buildkite_cluster_queue.kubernetes.key
}

output "agent_token" {
  value     = buildkite_cluster_agent_token.kubernetes.token
  sensitive = true
}

output "performance_pipeline_slug" {
  value = buildkite_pipeline.performance.slug
}

output "registry_slug" {
  value = buildkite_registry.oci.slug
}
