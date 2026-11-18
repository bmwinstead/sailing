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

variable "aws_region" {
  description = "AWS region of the SSM parameter that holds the Cloudflare API token"
  type        = string
  default     = "us-east-2"
}

variable "zone_name" {
  description = "Cloudflare zone that holds the Email Routing rule for the package address"
  type        = string
  default     = "winstead.io"
}

variable "pkg_mail_address" {
  description = "Package mailbox address. It is the Email Routing match and the Stalwart login name of the Worker."
  type        = string
  default     = "packages@pkg.winstead.io"
}

variable "pkg_mail_jmap_url" {
  description = "Public URL of the Stalwart JMAP route (Cloudflare Tunnel + Access)"
  type        = string
  default     = "https://pkg-ingest.winstead.io"
}
