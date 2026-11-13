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

variable "registry_name" {
  description = "Name of the team that owns the registries. Letters and numbers only. Immutable registry team_ids tie the registries to it."
  type        = string
  default     = "sailing"
}

variable "manifests_registry_name" {
  description = "OCI registry for the k8s manifests artifacts that Flux pulls (one image per repo)."
  type        = string
  default     = "manifests"
}

variable "images_registry_name" {
  description = "OCI registry for app images (one image per repo)."
  type        = string
  default     = "images"
}

variable "cooking_repo_url" {
  description = "Native entire:// URL of the cooking repo (as shown by the Buildkite Entire connection)"
  type        = string
  default     = "entire://aws-us-east-2.entire.io/et/winstead-io/cooking"
}
