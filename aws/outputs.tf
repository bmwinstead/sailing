output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "sops_kms_key_id" {
  value = aws_kms_key.sops.key_id
}

output "sops_kms_key_arn" {
  value = aws_kms_key.sops.arn
}

output "sops_kms_alias_name" {
  value = aws_kms_alias.sailing.name
}

output "region" {
  value = var.region
}

output "ssm_path_prefix" {
  value = var.ssm_path_prefix
}

output "tofu_access_key_id" {
  value     = aws_iam_access_key.tofu.id
  sensitive = true
}

output "tofu_secret_access_key" {
  value     = aws_iam_access_key.tofu.secret
  sensitive = true
}

output "flux_sops_access_key_id" {
  value     = aws_iam_access_key.flux_sops.id
  sensitive = true
}

output "flux_sops_secret_access_key" {
  value     = aws_iam_access_key.flux_sops.secret
  sensitive = true
}

output "stalwart_access_key_id" {
  value     = aws_iam_access_key.stalwart.id
  sensitive = true
}

output "stalwart_secret_access_key" {
  value     = aws_iam_access_key.stalwart.secret
  sensitive = true
}
