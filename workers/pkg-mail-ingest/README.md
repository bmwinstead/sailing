# pkg-mail-ingest

This Worker puts package emails into a Stalwart mailbox in the cluster. Home Assistant reads the mailbox.
No inbound mail port is open on the cluster.

## Flow

```text
Shipper or Proton filter
  -> packages@bmwinstead.com
  -> Cloudflare Email Routing
  -> Email Worker pkg-mail-ingest
  -> HTTPS to pkg-ingest.winstead.io (Cloudflare Access service token)
  -> Cloudflare Tunnel (wildcard route to envoy-external)
  -> HTTPRoute pkg-ingest (path /jmap only)
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

### 1.3 Sign in and set the listeners

Flux makes the domain `bmwinstead.com`, the account `packages@bmwinstead.com`, its two app passwords, and the admin role of your account (steps 1.4 and 1.6).
Do not make them by hand.

1. Open `https://stalwart.winstead.io/admin`. This is an internal HTTPRoute (LAN only).
   Sign in as `admin` with the password from step 1.1.
2. If the sign-in page fails, use JMAP with `curl` and the same credential.
   The old bootstrap mode needed a port-forward to `http://localhost:8080/admin`. This mode may not accept it.
   The HelmRelease sets `STALWART_PUBLIC_URL` so that Stalwart trusts the host `stalwart.winstead.io`.
3. Disable the SMTP, POP3, and ManageSieve listeners. Keep the HTTP listener on port 8080 and the IMAPS listener on port 993.
   The Kubernetes Service exposes only these two ports. Disable the other listeners to keep the config clean.

Check that the HTTP listener on port 8080 still exists after you change the listeners. The Kubernetes probes and the Envoy routes use it.

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
7. Create or update the domain `bmwinstead.com`. The domain made by hand is kept.
8. Set the role Administrator on the account `bmw@winstead.io`. Create the account `packages@bmwinstead.com` with the role User and no password.
   The plan finds each account by its name and its domain.
   If `bmw` does not exist yet, the plan creates it without a password. The first Pocket ID sign-in then uses that account.

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
5. The plan gives the account `bmw` the role Administrator (step 8 of the plan).
   For a different user name, change the `bmw` entry in `plan.ndjson`.
   If the account did not exist when the Job ran, delete the Job to run the plan again (see above).
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

### 1.6 App passwords and ids in AWS SSM

Pocket ID owns the account credentials, so the account `packages` has no password.
App passwords still work, but Stalwart makes the secret and shows it one time.
The Job `stalwart-pkg-credentials` makes the app passwords and stores them in AWS SSM Parameter Store (region `us-east-2`).
OpenTofu reads them from there.

The Job writes these parameters:

| Parameter | Type | Value |
| --- | --- | --- |
| `/sailing/tofu/pkg-mail-worker-password` | SecureString (`alias/sailing`) | The app password `pkg-mail-worker` |
| `/sailing/tofu/pkg-mail-ha-password` | SecureString (`alias/sailing`) | The app password `pkg-mail-home-assistant` |
| `/sailing/tofu/pkg-mail-account-id` | String | The JMAP account ID of `packages` (`ACCOUNT_ID` of the Worker) |
| `/sailing/tofu/pkg-mail-inbox-id` | String | The ID of its mailbox with the role `inbox` (`INBOX_ID` of the Worker) |

The user name for both app passwords is `packages@bmwinstead.com`.
`just aws put-secret` is only for values that you type yourself. Do not use it for these parameters.

The app password `pkg-mail-worker` can only sign in, upload a blob, and import an email (`authenticate`, `jmapBlobUpload`, `jmapEmailImport`).
The app password `pkg-mail-home-assistant` can only sign in over IMAP and read mail. It cannot append, copy, move, delete, or expunge.

For each app password, the Job does this:

1. If Stalwart has exactly one app password with that description and the SSM parameter exists, it does nothing.
2. If not, it deletes the app passwords with that description, makes a new one, and writes the secret to SSM.

So after a Stalwart reset, the Job makes new app passwords and replaces the old values in SSM.
The Job signs in as the recovery admin (Secret `stalwart-admin`) and acts on the account `packages`.
It writes to SSM as the IAM user `sailing-stalwart` (Secret `stalwart-aws-credentials`, see `aws/README.md`).
It never prints a secret.

Before the first run, the owner must do these steps in this order:

1. In `aws/`, run `just aws apply`. It creates the IAM user `sailing-stalwart`.
2. Run `just aws sync-stalwart-secret`. It writes `kubernetes/apps/default/stalwart/config/aws-credentials.sops.yaml`.
3. Commit that file. Then merge. Without the file, Flux cannot build `stalwart-config`.

Check the Job:

```sh
kubectl --kubeconfig=kubeconfig -n default get job stalwart-pkg-credentials
kubectl --kubeconfig=kubeconfig -n default logs job/stalwart-pkg-credentials
```

- The Job can start before the `stalwart-config` Job has made the account. Then it fails with `no account packages@bmwinstead.com yet` and tries again.
- The Job runs again only when its script or its manifest changes, or when you delete it.
  After a Stalwart reset, delete it: `kubectl --kubeconfig=kubeconfig -n default delete job stalwart-pkg-credentials`.
  Then run `flux --kubeconfig=kubeconfig -n default reconcile ks stalwart-config`.
- To replace one app password, delete its SSM parameter and then delete the Job.
- The mailbox moved from `pkg.winstead.io` to `bmwinstead.com`. The plan does not delete objects.
  The old domain `pkg.winstead.io` and the old account `packages@pkg.winstead.io` stay in Stalwart until you delete them in the WebUI.
  The Job reads only the account `packages` in the domain `bmwinstead.com`, so the old objects do no harm.

## 2. Get the account ID and the inbox ID

The Job `stalwart-pkg-credentials` writes both values to SSM (step 1.6).
`/sailing/tofu/pkg-mail-account-id` is `ACCOUNT_ID`. `/sailing/tofu/pkg-mail-inbox-id` is `INBOX_ID`.
Read them:

```sh
aws ssm get-parameters --region us-east-2 --names /sailing/tofu/pkg-mail-account-id /sailing/tofu/pkg-mail-inbox-id \
  --query 'Parameters[].[Name,Value]' --output text
```

## 3. Deploy with OpenTofu

OpenTofu deploys the Worker. The module is `cloudflare/` (file `pkg_mail_worker.tf`). Do not run `wrangler deploy`.
OpenTofu uploads `src/index.js`, and it sets the variables and the secrets as Worker bindings.
It reads most values from AWS SSM Parameter Store (path `/sailing/tofu/`).
The Cloudflare Access service token and application come from `cloudflare/pkg_mail_access.tf`. You do not make them by hand.
The `wrangler.toml` file is for local development only. Its `REPLACE_ME` values are placeholders. OpenTofu does not read them.
OpenTofu reads only `compatibility_date` from this file.

| SSM parameter | Binding | Written by |
|---|---|---|
| `pkg-mail-worker-password` | `STALWART_PASSWORD` (secret) | Automatic. The Stalwart Job writes the app password. |
| `pkg-mail-account-id` | `ACCOUNT_ID` | Automatic. The Stalwart Job writes it. |
| `pkg-mail-inbox-id` | `INBOX_ID` | Automatic. The Stalwart Job writes it. |
| `pkg-mail-fallback-addr` | `FALLBACK_ADDR` | You. |

OpenTofu sets `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` (secret) from the service token `pkg-mail-worker`.
OpenTofu sets two more bindings from variables with a default: `STALWART_USER` (`pkg_mail_address`, `packages@bmwinstead.com`) and `JMAP_URL` (`pkg_mail_jmap_url`).

Store the one value that you enter by hand. The command asks for the value at a hidden prompt:

```sh
just aws put-secret pkg-mail-fallback-addr
```

Then deploy. The Flux object `Terraform/cloudflare` in `flux-system` applies the module on its own after the merge to `main` (see `kubernetes/apps/flux-system/tofu-controller/README.md`).
To preview on the laptop, run `just cloudflare init` and `just cloudflare plan` in the repository root. Set `TF_VAR_account_id` first.

The apply fails if one SSM parameter does not exist. The controller tries again each hour.
Write all four parameters before you merge this change. The Stalwart Job writes three of them.
The OpenTofu state holds all of these values in plain text. The state bucket is encrypted. See `cloudflare/provider.tf`.

OpenTofu also makes these objects:

- The Access service token `pkg-mail-worker`.
- The Access policy `pkg-mail-worker`. It uses the action Service Auth (`non_identity`) and allows only that token.
- The Access application for `pkg-ingest.winstead.io`. It denies every other request with a 401 and has no login page.
- Email Routing for the zone `bmwinstead.com` (`cloudflare_email_routing_dns`).
- The Email Routing destination address `FALLBACK_ADDR`.

The Kubernetes side is in `kubernetes/apps/default/stalwart/app/helmrelease.yaml`.
The route `ingest` serves `pkg-ingest.winstead.io` on `envoy-external` and matches only the path prefix `/jmap`.
The tunnel already sends `*.winstead.io` to `envoy-external`, and external-dns makes the DNS record. Do not change the tunnel.

The Cloudflare API token needs these permissions, in addition to those in `cloudflare/provider.tf`:

- Account > Workers Scripts > Edit
- Account > Access: Apps and Policies > Edit
- Account > Access: Service Tokens > Edit
- Account > Email Routing Addresses > Edit
- Zone > Email Routing Rules > Edit, on the zone `bmwinstead.com`
- Zone > Zone > Read, on the zone `bmwinstead.com` (OpenTofu finds the zone ID by name)
- Zone > Zone Settings > Edit, on the zone `bmwinstead.com` (OpenTofu turns on Email Routing)
- Zone > DNS > Edit, on the zone `bmwinstead.com` (Email Routing makes the MX and SPF records)

If the token is for one zone only, use the all-zones scope for these permissions.
Never give the token an Email Routing job on `winstead.io`. That zone has Proton MX records.

If you already deployed the Worker or made the Email Routing rule by hand, import them before you merge.
Otherwise the apply fails with a conflict. Run these on the laptop:

```sh
cd cloudflare
tofu import cloudflare_workers_script.pkg_mail_ingest ACCOUNT_ID/pkg-mail-ingest
tofu import cloudflare_email_routing_rule.pkg_mail ZONE_ID/RULE_ID
```

Not verified: I did not run `plan` or `apply`, because the pod has no AWS or Cloudflare credentials.
The controller applies plans on its own, so run `just cloudflare plan` on the laptop before you merge.
I checked the resource shapes only with `tofu validate` against provider 5.29.0.
I did not test the Access policy against a live Worker request. After the first apply, run these two tests.
The first call must return 401 from Access. The second call must not reach Stalwart.

```sh
curl -i https://pkg-ingest.winstead.io/jmap/session
curl -i https://pkg-ingest.winstead.io/admin
```

Check the first `plan`. Cloudflare may return the bindings in a different order, which shows as a change on each plan.

## 4. Set up Email Routing

The mailbox uses the zone `bmwinstead.com`. This zone has no other mail service and no MX records.
Do not use `winstead.io`: Email Routing cannot run on a subdomain there, and the zone has Proton MX records.
The variable `pkg_mail_zone_name` refuses `winstead.io` and its subdomains.

OpenTofu turns on Email Routing for `bmwinstead.com`. Cloudflare then makes and locks the MX and SPF records.
OpenTofu makes the rule that sends `packages@bmwinstead.com` to the Worker `pkg-mail-ingest` (step 3).
OpenTofu also makes the destination address `FALLBACK_ADDR`. Do not add these by hand.
If Email Routing is already on for the zone, import it first: `tofu import cloudflare_email_routing_dns.pkg_mail ZONE_ID`.

One step stays manual: after the first apply, Cloudflare sends a verification email to `FALLBACK_ADDR`.
Open the email and confirm it. The Worker cannot forward to the address before you confirm it.

Not verified: the provider docs do not say that `cloudflare_email_routing_dns` makes the DKIM record.
After the first apply, open Email > Email Routing in the dashboard for `bmwinstead.com`.
Check that the status is Ready and that the DNS records are there.

Do not add the rule by hand. Check it in the dashboard after the apply.

## 5. Forward Proton email

WARNING: The Proton forwarding address must be `packages@bmwinstead.com`. The old address `packages@pkg.winstead.io` does not receive mail.

1. In Proton, add `packages@bmwinstead.com` as a forwarding address.
2. Proton sends a confirmation email to that address. The email goes to Stalwart.
3. Read the confirmation email. Use an IMAPS client through a port-forward
   (`kubectl --kubeconfig=kubeconfig -n default port-forward svc/stalwart 993:993`),
   or use the JMAP method `Email/query` with `Email/get`.
4. Open the confirmation link in the email.
5. Add a Proton filter that forwards shipping emails to `packages@bmwinstead.com`.

## 6. Set up Home Assistant

Install Mail and Packages with HACS. Use these settings:

- Host: `stalwart.default.svc.cluster.local`
- Port: `993`, SSL
- Username: `packages@bmwinstead.com`
- Password: the Home Assistant app password. Read it from SSM:

  ```sh
  aws ssm get-parameter --region us-east-2 --name /sailing/tofu/pkg-mail-ha-password --with-decryption --query Parameter.Value --output text
  ```

- Verify SSL: off. The certificate is self-signed and the connection stays inside the cluster.
- Folder: `INBOX`
- Forwarded emails: add the Proton addresses that forward mail.

## Follow-ups

- Add a CronJob that deletes old mail. Use JMAP `Email/query` for mail older than 30 days. Then use `Email/set` with `destroy`.
- Decide how to back up the CNPG cluster `stalwart-db`. It holds all mail and all Stalwart settings.
- Add a Home Assistant alert when no mail arrives for several days.
