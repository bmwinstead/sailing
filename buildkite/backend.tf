# The state bucket and the key come from the aws module. See ../aws/README.md.
# The backend cannot use variables, so the values are written out here.
terraform {
  backend "s3" {
    bucket       = "winstead-tfstate"
    key          = "buildkite/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:338208726210:key/5f27f89c-2f4e-49c9-9263-63596049bde5"
    use_lockfile = true
  }
}
