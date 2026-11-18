# Default key policy (root account kms:*), no alias, no tags. Rotation is off
# because the live key has it off. Changing that is a separate decision.
resource "aws_kms_key" "sops" {
  description         = "KMS Key for SOPS encryption"
  enable_key_rotation = false

  lifecycle {
    prevent_destroy = true
  }
}
