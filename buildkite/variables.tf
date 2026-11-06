variable "cluster_name" {
  description = "Buildkite cluster name"
  type        = string
  default     = "Kubernetes"
}

variable "queue_key" {
  description = "Cluster queue key. Must match config.tags (queue=<key>) in kubernetes/apps/buildkite/agent-stack-k8s/app/helmrelease.yaml."
  type        = string
  default     = "kubernetes"
}
