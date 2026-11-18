#!/usr/bin/env bash
# Mints the app passwords of the package mailbox and stores them, with its JMAP ids, in SSM.
# Safe to run again: it mints a password only if Stalwart or SSM does not have it.
set -euo pipefail

: "$STALWART_URL" "$STALWART_USER" "$STALWART_PASSWORD" "$LOGIN" "$SSM_PREFIX" "$KMS_KEY_ID"

log() { printf '%s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 1
}

umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# curl reads the credential from a file, so it is not in any argv.
printf 'header = "Authorization: Basic %s"\n' \
  "$(printf '%s:%s' "$STALWART_USER" "$STALWART_PASSWORD" | base64 | tr -d '\n')" >"$tmp/curl.conf"

# Sends the JMAP request on stdin. Prints the response. Fails on any method error.
jmap() {
  local response
  response="$(curl -fsS --retry 5 --retry-connrefused -K "$tmp/curl.conf" \
    -H 'content-type: application/json' --data-binary @- "$STALWART_URL/jmap/")"
  if jq -e 'any(.methodResponses[]; .[0] == "error")' <<<"$response" >/dev/null; then
    jq -c '.methodResponses[] | select(.[0] == "error") | .[1]' <<<"$response" >&2
    return 1
  fi
  printf '%s' "$response"
}

# Prints the stored value (the ciphertext for a SecureString), or nothing if the parameter does not exist.
ssm_get() {
  local out
  if out="$(aws ssm get-parameter --name "$1" --query Parameter.Value --output text 2>&1)"; then
    printf '%s' "$out"
  elif [[ "$out" != *ParameterNotFound* ]]; then
    log "$out"
    return 1
  fi
}

# Stores stdin as the parameter value. The value never goes into argv.
ssm_put() {
  jq -Rs --arg name "$1" --arg type "$2" --arg key "$KMS_KEY_ID" \
    '{Name: $name, Value: ., Type: $type, Overwrite: true} + if $type == "SecureString" then {KeyId: $key} else {} end' \
    >"$tmp/put.json"
  aws ssm put-parameter --cli-input-json "file://$tmp/put.json" >/dev/null
  rm -f "$tmp/put.json"
  log "stored $1"
}

name="${LOGIN%@*}"
domain="${LOGIN#*@}"

# The stalwart-config Job creates the account. Until it does, this Job fails and Kubernetes retries it.
account_id="$(jq -n '{
  using: ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
  methodCalls: [
    ["x:Domain/query", {}, "dq"],
    ["x:Domain/get", {"#ids": {resultOf: "dq", name: "x:Domain/query", path: "/ids"}, properties: ["name"]}, "dg"],
    ["x:Account/query", {}, "aq"],
    ["x:Account/get", {"#ids": {resultOf: "aq", name: "x:Account/query", path: "/ids"}, properties: ["name", "domainId"]}, "ag"]
  ]}' | jmap | jq -r --arg name "$name" --arg domain "$domain" '
  [.methodResponses[1][1].list[] | select(.name == $domain) | .id] as $domains
  | [.methodResponses[3][1].list[] | select(.name == $name and (.domainId | IN($domains[]))) | .id]
  | if length == 1 then .[0] else empty end')"
[ -n "$account_id" ] || die "no account $LOGIN yet"
log "account $LOGIN has JMAP id $account_id"

inbox_id="$(jq -n --arg account "$account_id" '{
  using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  methodCalls: [["Mailbox/get", {accountId: $account, ids: null, properties: ["role"]}, "m"]]
  }' | jmap | jq -r '[.methodResponses[0][1].list[] | select(.role == "inbox") | .id] | if length == 1 then .[0] else empty end')"
[ -n "$inbox_id" ] || die "no inbox for $LOGIN"
log "inbox of $LOGIN has id $inbox_id"

for pair in "pkg-mail-account-id=$account_id" "pkg-mail-inbox-id=$inbox_id"; do
  param="$SSM_PREFIX/${pair%%=*}"
  current="$(ssm_get "$param")"
  [ "$current" = "${pair#*=}" ] || printf '%s' "${pair#*=}" | ssm_put "$param" String
done

passwords="$(jq -n --arg account "$account_id" '{
  using: ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
  methodCalls: [
    ["x:AppPassword/query", {accountId: $account}, "q"],
    ["x:AppPassword/get", {accountId: $account, "#ids": {resultOf: "q", name: "x:AppPassword/query", path: "/ids"}, properties: ["description"]}, "g"]
  ]}' | jmap | jq -c '.methodResponses[1][1].list')"

# Arguments: the app password description, the SSM parameter name, the permission names.
mint() {
  local description="$1" param="$SSM_PREFIX/$2" stale stored response
  shift 2
  stale="$(jq -c --arg d "$description" '[.[] | select(.description == $d) | .id]' <<<"$passwords")"
  stored="$(ssm_get "$param")"
  if [ "$(jq length <<<"$stale")" = 1 ] && [ -n "$stored" ]; then
    log "kept app password $description"
    return
  fi
  response="$(jq -n --arg account "$account_id" --arg d "$description" --argjson stale "$stale" \
    --args '{
    using: ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
    methodCalls: [
      ["x:AppPassword/set", {accountId: $account, destroy: $stale}, "d"],
      ["x:AppPassword/set", {accountId: $account, create: {new: {
        description: $d,
        permissions: {"@type": "Replace", permissions: ($ARGS.positional | map({(.): true}) | add)}
      }}}, "c"]
    ]}' "$@" | jmap)"
  if ! jq -e '.methodResponses[1][1].created.new.secret | strings' <<<"$response" >/dev/null ||
    jq -e '.methodResponses[0][1].notDestroyed // {} | length > 0' <<<"$response" >/dev/null; then
    jq -c '[.methodResponses[][1] | {notDestroyed, notCreated}]' <<<"$response" >&2
    die "could not replace app password $description"
  fi
  jq -j '.methodResponses[1][1].created.new.secret' <<<"$response" | ssm_put "$param" SecureString
  log "minted app password $description"
}

# The Worker uploads the raw message and imports it (src/index.js). The HTTP upload endpoint checks only authenticate.
mint pkg-mail-worker pkg-mail-worker-password \
  authenticate jmapBlobUpload jmapEmailImport
# Home Assistant (Mail and Packages) signs in over IMAP and reads the inbox.
mint pkg-mail-home-assistant pkg-mail-ha-password \
  authenticate imapAuthenticate imapCapability imapId imapEnable imapNamespace imapList imapLsub \
  imapStatus imapSelect imapExamine imapSearch imapSort imapThread imapFetch imapStore imapIdle
