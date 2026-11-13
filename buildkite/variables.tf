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

variable "performance_repo_url" {
  description = "Native entire:// URL of the performance repo (as shown by the Buildkite Entire connection)"
  type        = string
  default     = "entire://aws-us-east-2.entire.io/et/winstead-io/performance"
}

variable "cooking_repo_url" {
  description = "Native entire:// URL of the cooking repo (as shown by the Buildkite Entire connection)"
  type        = string
  default     = "entire://aws-us-east-2.entire.io/et/winstead-io/cooking"
}

variable "registry_name" {
  description = "Buildkite Packages OCI registry (and owning team) name. Letters and numbers only."
  type        = string
  default     = "sailing"
}
