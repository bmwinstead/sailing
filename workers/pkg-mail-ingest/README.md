# pkg-mail-ingest

This Worker puts package emails into a Stalwart mailbox in the cluster. Home Assistant reads the mailbox.
No inbound mail port is open on the cluster.

## Flow

```text
Shipper or Proton filter
  -> packages@pkg.winstead.io
  -> Cloudflare Email Routing
  -> Email Worker pkg-mail-ingest
  -> HTTPS to pkg-ingest.winstead.io (Cloudflare Access service token)
  -> Cloudflare Tunnel (route /jmap only)
  -> Stalwart (JMAP, port 8080, namespace default)
  -> Home Assistant (Mail and Packages) over IMAPS, port 993
```

The Worker does not parse the email. It sends the raw message to Stalwart.
If the upload fails, the Worker forwards the email to `FALLBACK_ADDR`. No email is lost.

## Files

- `wrangler.toml`: Worker name and the settings for local development. OpenTofu deploys the Worker.
- `src/index.js`: the Worker code.
- `../../kubernetes/apps/default/stalwart`: the Stalwart deployment and its CNPG database (Flux).

## 1. Start Stalwart and set it up

Flux deploys Stalwart v1.1.1 from `kubernetes/apps/default/stalwart`.
Stalwart keeps all data in a CloudNativePG (CNPG) Postgres cluster named `stalwart-db`. There is no config volume.
The HelmRelease holds a small `config.json`. It describes only the data store.
The database password comes from the Secret `stalwart-db-app`, which CNPG creates.
The blob store, the search store, and the in-memory store use their defaults.
Blobs and search data stay in Postgres. The in-memory store stays in the process.

Because `config.json` exists, Stalwart does not start in bootstrap mode.
There is no setup wizard and no temporary password in the logs.
On the first start, Stalwart fills the empty database with default settings and listeners.
No admin account exists yet. The recovery admin credential in step 1.1 is the first sign-in.

### 1.1 Read the admin password

The Secret `stalwart-admin` is in git, encrypted with SOPS (`kubernetes/apps/default/stalwart/app/secret.sops.yaml`).
Its key `STALWART_RECOVERY_ADMIN` has the value format `admin:PASSWORD`.
Its keys `STALWART_USER` (`admin`) and `STALWART_PASSWORD` (`PASSWORD`) hold the same pair for the `stalwart-config` Job (step 1.4).
Read the password:

```sh
sops -d --extract '["stringData"]["STALWART_RECOVERY_ADMIN"]' kubernetes/apps/default/stalwart/app/secret.sops.yaml
```

The HelmRelease reads this Secret as optional. This credential works even when the directory has no admin.
Keep the Secret. The `stalwart-config` Job signs in with it.
If you change the Secret, restart the pod: `kubectl --kubeconfig=kubeconfig -n default rollout restart deploy/stalwart`

### 1.2 Check the start

1. Wait until the database is healthy:
   `kubectl --kubeconfig=kubeconfig -n default get cluster stalwart-db`
2. Wait until the pod is ready:
   `kubectl --kubeconfig=kubeconfig -n default get pods -l app.kubernetes.io/name=stalwart`
3. If the pod does not start, read the logs:
   `kubectl --kubeconfig=kubeconfig -n default logs deploy/stalwart`
   A bad database password or host shows as a `Startup failed` error.

### 1.3 Sign in and make the accounts

1. Open `https://stalwart.winstead.io/admin`. This is an internal HTTPRoute (LAN only).
   Sign in as `admin` with the password from step 1.1.
2. If the sign-in page fails, use JMAP with `curl` and the same credential (step 2 shows the calls).
   The old bootstrap mode needed a port-forward to `http://localhost:8080/admin`. This mode may not accept it.
   The HelmRelease sets `STALWART_PUBLIC_URL` so that Stalwart trusts the host `stalwart.winstead.io`.
3. Create the domain `pkg.winstead.io`.
4. Create the account `packages@pkg.winstead.io`.
5. Create two app passwords for that account. One is for the Worker. One is for Home Assistant.
   Do not use the account password. It stops working when Pocket ID becomes the default directory (step 1.4).
6. Make your personal account an admin (step 1.4). Keep the Secret `stalwart-admin`.
7. Disable the SMTP, POP3, and ManageSieve listeners. Keep the HTTP listener on port 8080 and the IMAPS listener on port 993.
   The Kubernetes Service exposes only these two ports. Disable the other listeners to keep the config clean.

Check that the HTTP listener on port 8080 still exists after you change the listeners. The Kubernetes probes and the tunnel use it.

### 1.4 Sign in with Pocket ID

Stalwart keeps the sign-in settings in its database, not in `config.json`. Flux writes them from git.
The Flux Kustomization `stalwart-config` runs the Job `stalwart-config`.
The Job runs `stalwart-cli apply` with the plan `kubernetes/apps/default/stalwart/config/plan.ndjson`.
The Pocket ID client `stalwart` is public and uses PKCE. The `stalwart` Flux app creates it.

CAUTION: The OIDC directory becomes the default directory for all domains.
After the Job runs, an account password does not work for IMAP, JMAP, or the WebUI.
App passwords, API keys, and the recovery admin password continue to work. Stalwart checks them before the directory.

The plan does these steps in this order:

1. Create or update the domain `winstead.io`.
2. Create or update the OIDC directory `Pocket ID`. Its issuer is `https://id.winstead.io` and its accepted audience is `stalwart`.
3. Set this directory as `directoryId` on the `Authentication` object. Without this link, the WebUI does not find Pocket ID.
4. Create or update the internal OAuth client `stalwart`. The recovery admin signs in to the WebUI with it.
5. Set the OAuth client ID `stalwart` and the scopes `profile email` on the Application `Stalwart Web Interface`.
6. Reload the settings and the web applications. Stalwart does not restart.

The plan finds each object by its description or client ID. You can run the plan again. It does not make duplicates.
If no Application has the description `Stalwart Web Interface`, the Job fails.

The Job signs in as the recovery admin with the keys `STALWART_USER` and `STALWART_PASSWORD` of the Secret `stalwart-admin`.

Check the Job:

```sh
flux --kubeconfig=kubeconfig -n default get ks stalwart-config
kubectl --kubeconfig=kubeconfig -n default get job stalwart-config
kubectl --kubeconfig=kubeconfig -n default logs job/stalwart-config
```

- The Job can start before Stalwart is ready. Then it fails, waits longer each time, and tries again (20 times at most).
- `CreateContainerConfigError` on the pod means that the Secret has no `STALWART_USER` or `STALWART_PASSWORD` key.
- A failed `ReloadSettings` step means that Stalwart cannot load a setting.
  For example, Stalwart cannot read `https://id.winstead.io/.well-known/openid-configuration`.
  Read the Stalwart log: `kubectl --kubeconfig=kubeconfig -n default logs deploy/stalwart`

If you change the plan:

1. Keep one JSON object on each line.
2. Optional: check the plan with a dry run. The dry run needs a port-forward and the `stalwart-cli` binary.

   ```sh
   kubectl --kubeconfig=kubeconfig -n default port-forward svc/stalwart 8080:8080 &
   STALWART_URL=http://localhost:8080 STALWART_USER=admin STALWART_PASSWORD='PASSWORD' \
     stalwart-cli apply --file kubernetes/apps/default/stalwart/config/plan.ndjson --dry-run
   ```

3. Commit and push. The ConfigMap name has a hash of the plan, so the Job changes. Flux deletes the old Job and starts a new one (`force: true`).
4. Check the new Job log.

To run the same plan again, for example after a database reset, delete the Job. Flux makes it again:

```sh
kubectl --kubeconfig=kubeconfig -n default delete job stalwart-config
flux --kubeconfig=kubeconfig -n default reconcile ks stalwart-config
```

#### First sign-in and the admin role

Stalwart makes the account at the first Pocket ID sign-in.
The account address is the Pocket ID user name (`preferred_username`) and `@winstead.io`.
The display name comes from the `name` claim.

1. The plan creates the Stalwart domain `winstead.io`. Without it, the sign-in fails with `Account domain does not exist or has been disabled`.
   Stalwart makes DKIM keys for this domain. It has no SMTP listener, so it does not send mail.
2. Open `https://stalwart.winstead.io/admin`. Type `USERNAME@winstead.io`. The WebUI sends you to Pocket ID.
3. Sign in at Pocket ID. Stalwart makes the account with the role User.
4. Sign out. Sign in as `admin` with the password from step 1.1. The recovery admin always uses the Stalwart sign-in page.
5. Set the role of the new account to Administrator. In the WebUI, open the account. With the CLI:

   ```sh
   stalwart-cli query Account
   stalwart-cli update Account ACCOUNT_ID --json '{"roles":{"@type":"Admin"}}'
   ```

6. Sign out. Sign in again with Pocket ID.

Pocket ID groups do not give a Stalwart role. Stalwart uses groups only for shared access, and the plan does not read the `groups` claim.
Later sign-ins keep the role. A sign-in updates only the display name, the aliases, and the groups of the account.

The Pocket ID client allows only the `/admin` callback. The Account Manager at `/account` cannot sign in with Pocket ID.
To use it, add `https://stalwart.winstead.io/account/oauth/callback` to the client in `kubernetes/apps/default/stalwart/app/oidcclient.yaml`.

Verified: I read the Stalwart v1.1.1 and Pocket ID v2.19.2 source. I ran a CLI 2.0.0 dry run against the v1.1.1 schema.
Not verified: I did not run the Job against a live Stalwart. I did not test the Pocket ID sign-in, the role change, or the WebUI menu path.

### 1.5 Database notes

- The link to Postgres uses TLS but does not check the server certificate (`allowInvalidCerts`).
  CNPG signs the certificate with its own CA. Stalwart has no setting for a CA file, so it cannot check that CA.
  The traffic stays inside the cluster.
- `/var/lib/stalwart` is an empty directory that the pod loses at each restart. Stalwart keeps no state in it.
- To change the data store, edit `config.json` in the HelmRelease. Stalwart restarts on the change.

## 2. Get the account ID and the inbox ID

Get the account ID. Use the Worker account and its app password:

```sh
curl -s -u 'packages@pkg.winstead.io:PASSWORD' https://stalwart.winstead.io/jmap/session | jq '.primaryAccounts'
```

Copy the value of `urn:ietf:params:jmap:mail`. This value is `ACCOUNT_ID`.

Get the inbox ID:

```sh
curl -s -u 'packages@pkg.winstead.io:PASSWORD' https://stalwart.winstead.io/jmap/ \
  -H 'content-type: application/json' \
  -d '{"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"],
       "methodCalls":[["Mailbox/get",{"accountId":"ACCOUNT_ID"},"0"]]}' \
  | jq '.methodResponses[0][1].list[] | select(.role=="inbox") | .id'
```

This value is `INBOX_ID`. Put both values in `wrangler.toml`.

## 3. Add the Tunnel route

The `cloudflare-tunnel` app runs cloudflared with `TUNNEL_TOKEN` and the command `tunnel run`.
This is a remotely managed tunnel. The `ingress:` list in the cluster ConfigMap is not used.
Add the route in the Cloudflare dashboard. Do not edit the cluster.

1. Open Cloudflare Zero Trust. Go to Networks > Tunnels. Select the cluster tunnel.
2. Open Published application routes. Add a route:
   - Hostname: `pkg-ingest.winstead.io`
   - Path: `^/jmap(/.*)?$`
   - Service: `http://stalwart.default.svc.cluster.local:8080`
3. Put this route above any wildcard route for `*.winstead.io`. The tunnel matches routes in order.

Cloudflare creates the DNS record for a published route. Do not add the record by hand.
Only `/jmap` is routed. The admin UI is never reachable through the tunnel.

Not verified: I could not confirm that the dashboard accepts a regex in the Path field.
The cloudflared `ingress` rules use a regex for `path`. If the dashboard rejects the value, use `/jmap`.
After you save the route, run this test. The first call must return 401 or 403 from Access. The admin path must not reach Stalwart.

```sh
curl -i https://pkg-ingest.winstead.io/jmap/session
curl -i https://pkg-ingest.winstead.io/admin
```

## 4. Protect the route with Cloudflare Access

1. In Zero Trust, go to Access > Service credentials > Service Tokens. Create a token.
   Copy the Client ID and the Client Secret. The secret shows once.
2. Go to Access > Applications. Add a Self-hosted application.
   - Destination hostname: `pkg-ingest.winstead.io`
3. Add one policy. Set the action to Service Auth. Include the service token from step 1.
4. Save the application.

## 5. Deploy the Worker with OpenTofu

OpenTofu deploys the Worker. The module is `cloudflare/` (file `pkg_mail_worker.tf`). Do not run `wrangler deploy`.
OpenTofu uploads `src/index.js`, and it sets the variables and the secrets as Worker bindings.
It reads each value from AWS SSM Parameter Store (path `/sailing/tofu/`).
The `wrangler.toml` file is for local development only. Its `REPLACE_ME` values are placeholders. OpenTofu does not read them.
OpenTofu reads only `compatibility_date` from this file.

| SSM parameter | Binding | Written by |
|---|---|---|
| `pkg-mail-worker-password` | `STALWART_PASSWORD` (secret) | Automatic. The Stalwart Job writes the app password. |
| `pkg-mail-account-id` | `ACCOUNT_ID` | Automatic. The Stalwart Job writes it. |
| `pkg-mail-inbox-id` | `INBOX_ID` | Automatic. The Stalwart Job writes it. |
| `pkg-mail-access-client-id` | `CF_ACCESS_CLIENT_ID` (secret) | You, from step 4. |
| `pkg-mail-access-client-secret` | `CF_ACCESS_CLIENT_SECRET` (secret) | You, from step 4. |
| `pkg-mail-fallback-addr` | `FALLBACK_ADDR` | You. |

OpenTofu sets two more bindings from variables with a default: `STALWART_USER` (`pkg_mail_address`, `packages@pkg.winstead.io`) and `JMAP_URL` (`pkg_mail_jmap_url`).

Store the three values that you enter by hand. Each command asks for the value at a hidden prompt:

```sh
just aws put-secret pkg-mail-access-client-id
just aws put-secret pkg-mail-access-client-secret
just aws put-secret pkg-mail-fallback-addr
```

Then deploy. Run all of these in the repository root:

```sh
export TF_VAR_account_id=ACCOUNT_ID   # the Cloudflare account ID
just cloudflare init
just cloudflare plan
just cloudflare apply
```

`just cloudflare apply` fails if one SSM parameter does not exist. Run it after the Stalwart Job wrote its three parameters.
The OpenTofu state holds all of these values in plain text. The state bucket is encrypted. See `cloudflare/provider.tf`.

The Cloudflare API token needs these permissions, in addition to those in `cloudflare/provider.tf`:

- Account > Workers Scripts > Edit
- Zone > Email Routing Rules > Edit, on the zone `winstead.io`
- Zone > Zone > Read, on the zone `winstead.io` (OpenTofu finds the zone ID by name)

If you already deployed the Worker or made the Email Routing rule by hand, import them before the first apply.
Otherwise the apply fails with a conflict:

```sh
cd cloudflare
tofu import cloudflare_workers_script.pkg_mail_ingest ACCOUNT_ID/pkg-mail-ingest
tofu import cloudflare_email_routing_rule.pkg_mail ZONE_ID/RULE_ID
```

Not verified: I did not run `plan` or `apply`, because the pod has no AWS or Cloudflare credentials.
I checked the resource shapes only with `tofu validate` against provider 5.29.0.
Check the first `plan`. Cloudflare may return the bindings in a different order, which shows as a change on each plan.

## 6. Set up Email Routing

1. In the Cloudflare dashboard, open the zone `winstead.io`. Go to Email > Email Routing.
2. Enable Email Routing for the subdomain `pkg.winstead.io`. Add the DNS records that Cloudflare shows.
3. Go to Destination addresses. Add the `FALLBACK_ADDR` address. Open the verification email and confirm it.
4. OpenTofu makes the rule that sends `packages@pkg.winstead.io` to the Worker `pkg-mail-ingest` (step 5).
   Do not add this rule by hand. Check it in the dashboard after the apply.

## 7. Forward Proton email

1. In Proton, add `packages@pkg.winstead.io` as a forwarding address.
2. Proton sends a confirmation email to that address. The email goes to Stalwart.
3. Read the confirmation email. Use an IMAPS client through a port-forward
   (`kubectl --kubeconfig=kubeconfig -n default port-forward svc/stalwart 993:993`),
   or use the JMAP method `Email/query` with `Email/get`.
4. Open the confirmation link in the email.
5. Add a Proton filter that forwards shipping emails to `packages@pkg.winstead.io`.

## 8. Set up Home Assistant

Install Mail and Packages with HACS. Use these settings:

- Host: `stalwart.default.svc.cluster.local`
- Port: `993`, SSL
- Username: `packages@pkg.winstead.io`
- Password: the Home Assistant app password
- Verify SSL: off. The certificate is self-signed and the connection stays inside the cluster.
- Folder: `INBOX`
- Forwarded emails: add the Proton addresses that forward mail.

## Follow-ups

- Add a CronJob that deletes old mail. Use JMAP `Email/query` for mail older than 30 days. Then use `Email/set` with `destroy`.
- Decide how to back up the CNPG cluster `stalwart-db`. It holds all mail and all Stalwart settings.
- Add a Home Assistant alert when no mail arrives for several days.
