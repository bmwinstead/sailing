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

variable "pkg_mail_zone_name" {
  description = "Cloudflare zone for the package mailbox. OpenTofu turns on Email Routing for this zone and changes its MX records."
  type        = string
  default     = "bmwinstead.com"

  # winstead.io has Proton MX records. Email Routing would replace them and Proton mail would stop.
  validation {
    condition     = !can(regex("(^|\\.)winstead\\.io$", var.pkg_mail_zone_name))
    error_message = "Do not use winstead.io or a subdomain of it. The zone has Proton MX records."
  }
}

variable "pkg_mail_address" {
  description = "Package mailbox address. It is the Email Routing match and the Stalwart login name of the Worker. Its domain must be the pkg_mail_zone_name zone."
  type        = string
  default     = "packages@bmwinstead.com"

  validation {
    condition     = endswith(var.pkg_mail_address, "@${var.pkg_mail_zone_name}")
    error_message = "The address must end with @ and the value of pkg_mail_zone_name."
  }
}

variable "pkg_mail_jmap_url" {
  description = "Public URL of the Stalwart JMAP route (Cloudflare Tunnel + Access)"
  type        = string
  default     = "https://pkg-ingest.winstead.io"
}
