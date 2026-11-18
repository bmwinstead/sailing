# The Email Worker in ../workers/pkg-mail-ingest. OpenTofu is the deploy path.
# Most values come from SSM. The Access service token comes from pkg_mail_access.tf. See ../workers/pkg-mail-ingest/README.md for who writes each one.

locals {
  pkg_mail_worker_name = "pkg-mail-ingest"
  pkg_mail_worker_dir  = "${path.module}/../workers/pkg-mail-ingest"

  pkg_mail_ssm = toset([
    "pkg-mail-worker-password",
    "pkg-mail-account-id",
    "pkg-mail-inbox-id",
    "pkg-mail-fallback-addr",
  ])
}

data "aws_ssm_parameter" "pkg_mail" {
  for_each = local.pkg_mail_ssm
  name     = "/sailing/tofu/${each.key}"
}

# Bindings are sorted by name. Each value is sensitive, so the state and the plan hide it.
# The binding names are the names that src/index.js reads from env.
resource "cloudflare_workers_script" "pkg_mail_ingest" {
  account_id  = var.account_id
  script_name = local.pkg_mail_worker_name
  main_module = "index.js"
  content     = file("${local.pkg_mail_worker_dir}/src/index.js")
  # One source for the date: wrangler.toml keeps it for local dev.
  compatibility_date = regex("compatibility_date\\s*=\\s*\"([^\"]+)\"", file("${local.pkg_mail_worker_dir}/wrangler.toml"))[0]

  bindings = [
    { name = "ACCOUNT_ID", type = "plain_text", text = data.aws_ssm_parameter.pkg_mail["pkg-mail-account-id"].value },
    { name = "CF_ACCESS_CLIENT_ID", type = "secret_text", text = cloudflare_zero_trust_access_service_token.pkg_mail_worker.client_id },
    { name = "CF_ACCESS_CLIENT_SECRET", type = "secret_text", text = cloudflare_zero_trust_access_service_token.pkg_mail_worker.client_secret },
    { name = "FALLBACK_ADDR", type = "plain_text", text = data.aws_ssm_parameter.pkg_mail["pkg-mail-fallback-addr"].value },
    { name = "INBOX_ID", type = "plain_text", text = data.aws_ssm_parameter.pkg_mail["pkg-mail-inbox-id"].value },
    { name = "JMAP_URL", type = "plain_text", text = var.pkg_mail_jmap_url },
    { name = "STALWART_PASSWORD", type = "secret_text", text = data.aws_ssm_parameter.pkg_mail["pkg-mail-worker-password"].value },
    { name = "STALWART_USER", type = "plain_text", text = var.pkg_mail_address },
  ]
}

data "cloudflare_zone" "main" {
  filter = { name = var.zone_name }
}

# This rule sends mail for the package address to the Worker.
# The Email Routing setup for the subdomain stays manual. The destination address is in pkg_mail_access.tf.
resource "cloudflare_email_routing_rule" "pkg_mail" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = local.pkg_mail_worker_name
  enabled = true

  matchers = [{
    type  = "literal"
    field = "to"
    value = var.pkg_mail_address
  }]

  actions = [{
    type  = "worker"
    value = [cloudflare_workers_script.pkg_mail_ingest.script_name]
  }]
}
