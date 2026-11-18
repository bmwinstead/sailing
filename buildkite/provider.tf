# TODO(bryan): needs a real Buildkite API token. Nothing here runs
# automatically, and no token is stored in this repo.
#
# 1. Apply the aws module first (it creates the state bucket and the KMS key):
#      just aws plan && just aws apply     (see ../aws/README.md)
# 2. Create a Buildkite API access token. It needs these scopes: write_pipelines,
#    write_suites, read_pipelines, read_notification_services,
#    write_notification_services, read_organization_settings,
#    write_organization_settings and graphql. This link fills in the scopes:
#      https://buildkite.com/user/api-access-tokens/new?description=opentofu&scopes[]=write_pipelines&scopes[]=write_suites&scopes[]=read_pipelines&scopes[]=read_notification_services&scopes[]=write_notification_services&scopes[]=read_organization_settings&scopes[]=write_organization_settings&scopes[]=graphql
# 3. Store the token and the organization slug in AWS SSM Parameter Store.
#    Paste each value at the hidden prompt:
#      just aws put-secret buildkite-api-token
#      just aws put-secret buildkite-organization-slug
# 4. Sign in to AWS (aws login, or aws sso login --profile <profile>), then:
#      just buildkite init
# 5. just buildkite plan    # review: creates 1 cluster, 1 queue, 1 agent token
# 6. just buildkite apply
# 7. just buildkite sync-secret   # SOPS-encrypts the agent token into
#    kubernetes/apps/buildkite/agent-stack-k8s/app/secret-agent-token.sops.yaml
# 8. Add "./secret-agent-token.sops.yaml" to that app's kustomization.yaml
#    resources list, commit, push, `just kube reconcile`.
#
# Move old local state to S3 (only if buildkite/terraform.tfstate exists):
#   cp terraform.tfstate terraform.tfstate.pre-migrate
#   tofu init -migrate-state -force-copy
#   just buildkite plan     # must show no changes
# Keep terraform.tfstate.pre-migrate until the plan shows no changes.
#
# State is in the S3 bucket winstead-tfstate at buildkite/terraform.tfstate.
# The bucket encrypts it with the shared KMS key. It contains the agent token
# in plain text. Only identities that can use the key and read that prefix
# can read it.
provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "buildkite_api_token" {
  name = "/sailing/tofu/buildkite-api-token"
}

data "aws_ssm_parameter" "buildkite_organization_slug" {
  name = "/sailing/tofu/buildkite-organization-slug"
}

provider "buildkite" {
  api_token    = data.aws_ssm_parameter.buildkite_api_token.value
  organization = data.aws_ssm_parameter.buildkite_organization_slug.value
}
