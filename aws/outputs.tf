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
