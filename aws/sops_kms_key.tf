# One key for three uses: SOPS files, the OpenTofu state bucket and SSM
# SecureString parameters. Default key policy (root account kms:*), no tags.
# Do not manage the key policy here. IAM policies on users grant access.
resource "aws_kms_key" "sops" {
  description = "KMS key shared by SOPS, the OpenTofu state bucket and SSM SecureString parameters"

  # Rotation is off because the live key has it off. Rotation costs money
  # for each key version, so turning it on is a separate decision.
  enable_key_rotation = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "sailing" {
  name          = "alias/sailing"
  target_key_id = aws_kms_key.sops.key_id
}
