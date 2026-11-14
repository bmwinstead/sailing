output "bucket_name" {
  value = cloudflare_r2_bucket.cnpg_backups.name
}

output "s3_endpoint" {
  value = "https://${var.account_id}.r2.cloudflarestorage.com"
}

output "access_key_id" {
  value = cloudflare_account_token.cnpg_backups.id
}

output "secret_access_key" {
  value     = sha256(cloudflare_account_token.cnpg_backups.value)
  sensitive = true
}
