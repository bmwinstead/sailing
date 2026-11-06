# TODO(bryan): requires a real Buildkite API token — nothing here runs
# automatically, and no token is stored in this repo.
#
# 1. Create an API access token scoped for Terraform/OpenTofu (write/read
#    pipelines + organization settings + GraphQL):
#      https://buildkite.com/user/api-access-tokens/new?description=opentofu&scopes[]=write_pipelines&scopes[]=write_suites&scopes[]=read_pipelines&scopes[]=read_notification_services&scopes[]=write_notification_services&scopes[]=read_organization_settings&scopes[]=write_organization_settings&scopes[]=graphql
# 2. Export it (never commit it):
#      export BUILDKITE_API_TOKEN=bkua_...
#      export BUILDKITE_ORGANIZATION_SLUG=<your-org-slug>
# 3. just buildkite init
# 4. just buildkite plan    # review: creates 1 cluster, 1 queue, 1 agent token
# 5. just buildkite apply
# 6. just buildkite sync-secret   # SOPS-encrypts the agent token into
#    kubernetes/apps/buildkite/agent-stack-k8s/app/secret-agent-token.sops.yaml
# 7. Add "./secret-agent-token.sops.yaml" to that app's kustomization.yaml
#    resources list, commit, push, `just kube reconcile`.
#
# State (buildkite/terraform.tfstate) contains the agent token in plaintext —
# it's gitignored, not committed. This is a single-user homelab repo, so
# local state is fine; don't copy this as-is into a team setting without
# moving to a remote backend.
provider "buildkite" {}
