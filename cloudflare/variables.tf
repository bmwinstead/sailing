variable "account_id" {
  description = "Cloudflare account ID that owns the R2 bucket (Dashboard > account Overview > Account ID)"
  type        = string
}

variable "bucket_name" {
  description = "R2 bucket name for CloudNativePG (Barman Cloud) backups"
  type        = string
  default     = "cnpg-backups"
}

variable "bucket_location" {
  description = "R2 location hint. One of apac, eeur, enam, weur, wnam, oc. Only honored when the bucket is first created, and best-effort."
  type        = string
  default     = "enam"
}
