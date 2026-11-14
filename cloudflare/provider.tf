# TODO(bryan): requires a real Cloudflare API token — nothing here runs
# automatically, and no token is stored in this repo.
#
# 1. Create a Cloudflare API token (user token) with these permissions:
#      Dashboard > My Profile > API Tokens > Create Token > Create Custom Token
#      - Account > Workers R2 Storage > Edit      (creates the R2 bucket)
#      - Account > Account API Tokens > Edit      (creates the bucket-scoped token)
#    Set "Account Resources" to Include > the account that owns the bucket.
#    Edit includes Read, which the permission groups data source needs.
# 2. Export it (never commit it):
#      export CLOUDFLARE_API_TOKEN=...
# 3. just cloudflare init
# 4. just cloudflare plan    # review: creates 1 R2 bucket, 1 account API token
#    (pass the account with: export TF_VAR_account_id=<account-id>)
# 5. just cloudflare apply
# 6. just cloudflare sync-secret   # SOPS-encrypts the R2 credentials into
#    kubernetes/apps/default/home-assistant/app/secret-r2.sops.yaml
#    A later PR adds the Barman plugin and wires that file into a kustomization.
#
# State (cloudflare/terraform.tfstate) contains the account API token and the
# derived S3 secret key in plaintext — it's gitignored, not committed. This is
# a single-user homelab repo, so local state is fine; don't copy this as-is
# into a team setting without moving to a remote backend.
provider "cloudflare" {}
