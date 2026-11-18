resource "cloudflare_r2_bucket" "cnpg_backups" {
  account_id = var.account_id
  name       = var.bucket_name
  location   = var.bucket_location
}

data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.account_id
}

locals {
  # "Object Read & Write" in the dashboard. Looked up by name so no UUID is hard-coded.
  bucket_item_write = one([
    for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.id
    if g.name == "Workers R2 Storage Bucket Item Write"
  ])
}

# R2 S3 credentials derive from this token: access key ID = token id,
# secret access key = sha256 hex of the token value (see outputs.tf).
resource "cloudflare_account_token" "cnpg_backups" {
  account_id = var.account_id
  name       = "${var.bucket_name} (R2 object read & write)"

  policies = [{
    effect            = "allow"
    permission_groups = [{ id = local.bucket_item_write }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${var.account_id}_default_${cloudflare_r2_bucket.cnpg_backups.name}" = "*"
    })
  }]
}
