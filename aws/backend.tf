# The state lives in the bucket that this module manages. See README.md for
# the bootstrap. The bootstrap recipes swap this backend for a local one with
# backend_override.tf, which is not committed.
terraform {
  backend "s3" {
    bucket       = "winstead-tfstate"
    key          = "aws/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:338208726210:key/5f27f89c-2f4e-49c9-9263-63596049bde5"
    use_lockfile = true
  }
}
