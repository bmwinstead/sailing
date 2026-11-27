# Cloudflare Access for the JMAP route of the pkg-mail Worker (see ../workers/pkg-mail-ingest/README.md).
# Only the Worker can reach the host. The Worker sends this service token in each request.
# The Kubernetes HTTPRoute for the host is in kubernetes/apps/default/stalwart. external-dns makes the DNS record.

locals {
  pkg_mail_jmap_host = trimprefix(var.pkg_mail_jmap_url, "https://")
}

# The token never expires, so the Worker does not stop without a warning.
# To rotate the secret, increase client_secret_version.
resource "cloudflare_zero_trust_access_service_token" "pkg_mail_worker" {
  account_id = var.account_id
  name       = "pkg-mail-worker"
  duration   = "forever"
}

resource "cloudflare_zero_trust_access_policy" "pkg_mail_worker" {
  account_id = var.account_id
  name       = "pkg-mail-worker"
  decision   = "non_identity"

  include = [{
    service_token = { token_id = cloudflare_zero_trust_access_service_token.pkg_mail_worker.id }
  }]
}

# A request that does not match the policy is denied. There is no login page: Access returns 401.
resource "cloudflare_zero_trust_access_application" "pkg_mail_ingest" {
  account_id = var.account_id
  name       = "pkg-mail-ingest"
  type       = "self_hosted"
  domain     = local.pkg_mail_jmap_host

  destinations = [{
    type = "public"
    uri  = local.pkg_mail_jmap_host
  }]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.pkg_mail_worker.id
    precedence = 1
  }]

  app_launcher_visible      = false
  service_auth_401_redirect = true
}

# The Worker can forward to this address only after the owner confirms the verification email.
resource "cloudflare_email_routing_address" "pkg_mail_fallback" {
  account_id = var.account_id
  email      = data.aws_ssm_parameter.pkg_mail["pkg-mail-fallback-addr"].value
}
