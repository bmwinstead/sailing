# The state lives in the bucket that this module manages. See README.md for
# the bootstrap. The bootstrap recipes swap this backend for a local one with
# backend_override.tf, which is not committed.
terraform {
  backend "s3" {
    bucket       = "winstead-tfstate"
    key          = "aws/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
