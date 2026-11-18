variable "account_id" {
  description = "AWS account ID. The provider refuses to run against any other account."
  type        = string
  default     = "338208726210"
}

variable "region" {
  description = "AWS region of the state bucket and the SOPS KMS key"
  type        = string
  default     = "us-east-2"
}

variable "bucket_name" {
  description = "S3 bucket for OpenTofu state. Must match the bucket in backend.tf, which cannot use variables."
  type        = string
  default     = "winstead-tfstate"
}

variable "kms_key_id" {
  description = "ID of the existing SOPS KMS key. Only the bootstrap import uses it. On an empty account the bootstrap creates a new key."
  type        = string
  default     = "5f27f89c-2f4e-49c9-9263-63596049bde5"
}
