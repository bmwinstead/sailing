# TODO(bryan): needs a real Cloudflare API token. Nothing here runs
# automatically, and no token is stored in this repo.
#
# 1. Create a Cloudflare API token (user token) with these permissions:
#      Dashboard > My Profile > API Tokens > Create Token > Create Custom Token
#      - Account > Workers R2 Storage > Edit      (creates the R2 bucket)
#      - Account > Account API Tokens > Edit      (creates the bucket-scoped token)
#    Set "Account Resources" to Include > the account that owns the bucket.
#    Edit includes Read, which the permission groups data source needs.
# 2. Apply the aws module first (it creates the state bucket and the KMS key):
#      just aws plan && just aws apply     (see ../aws/README.md)
# 3. Store the token in AWS SSM Parameter Store. Paste it at the hidden prompt:
#      just aws put-secret cloudflare-api-token
# 4. Sign in to AWS (aws login, or aws sso login --profile <profile>), then:
#      cp local.auto.tfvars.example local.auto.tfvars   (in cloudflare/; git ignores it)
#      Put the Cloudflare account ID in local.auto.tfvars. OpenTofu loads it for plan, apply and import.
#      just cloudflare init
# 5. just cloudflare plan    # review: creates 1 R2 bucket, 1 account API token
# 6. just cloudflare apply
# 7. just cloudflare sync-secret   # SOPS-encrypts the R2 credentials into
#    kubernetes/apps/default/home-assistant/app/secret-r2.sops.yaml
#    A later PR adds the Barman plugin and wires that file into a kustomization.
#
# State is in the S3 bucket winstead-tfstate at cloudflare/terraform.tfstate.
# The bucket encrypts it with the shared KMS key. It contains the Cloudflare
# API token, the account API token and the derived S3 secret key in plain
# text. Only identities that can use the key and read that prefix can read it.
provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "cloudflare_api_token" {
  name = "/sailing/tofu/cloudflare-api-token"
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}
