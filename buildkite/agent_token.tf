# Consumed by kubernetes/apps/buildkite/agent-stack-k8s (the controller that
# creates a k8s Job per build step) via `just buildkite sync-secret`.
resource "buildkite_cluster_agent_token" "kubernetes" {
  cluster_id  = buildkite_cluster.sailing.id
  description = "agent-stack-k8s controller (kubernetes/apps/buildkite)"
}
