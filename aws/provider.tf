# No credential is stored in this repo. Sign in first, then run the recipes:
#   aws login                         (or: aws sso login --profile <profile>)
# For an SSO profile, also set AWS_PROFILE=<profile>. See README.md.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}
