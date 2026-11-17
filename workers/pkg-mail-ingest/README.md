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

- `wrangler.toml`: Worker name, variables, and the list of secrets.
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
No admin account exists yet. You must give Stalwart a recovery admin credential.

### 1.1 Create the admin Secret

The Secret is not in git. Make it with SOPS.
Choose a long password. The value format is `admin:PASSWORD`.

1. Create the file:

   ```sh
   cat > kubernetes/apps/default/stalwart/app/secret.sops.yaml <<'EOF'
   apiVersion: v1
   kind: Secret
   metadata:
     name: stalwart-admin
   stringData:
     STALWART_RECOVERY_ADMIN: admin:PASSWORD
   EOF
   sops --encrypt --in-place kubernetes/apps/default/stalwart/app/secret.sops.yaml
   ```

2. Add `./secret.sops.yaml` to `kubernetes/apps/default/stalwart/app/kustomization.yaml`.
3. Commit, push, and run `just kube reconcile`.
4. Restart the pod so that it reads the new Secret:
   `kubectl --kubeconfig=kubeconfig -n default rollout restart deploy/stalwart`

The HelmRelease reads this Secret as optional. Stalwart starts without it, but you cannot sign in.
This credential works even when the directory has no admin. Remove the Secret after you make a real admin account (step 1.3).

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
5. Create two app passwords for that account if Stalwart supports them. One is for the Worker. One is for Home Assistant.
   If Stalwart does not support them, use the account password.
6. Create a personal account with the Admin role. Sign in with it.
   Then delete the Secret `stalwart-admin`, take it out of the kustomization, and restart the pod.
7. Disable the SMTP, POP3, and ManageSieve listeners. Keep the HTTP listener on port 8080 and the IMAPS listener on port 993.
   The Kubernetes Service exposes only these two ports. Disable the other listeners to keep the config clean.

Check that the HTTP listener on port 8080 still exists after you change the listeners. The Kubernetes probes and the tunnel use it.

### 1.4 Sign in with Pocket ID (optional)

The Pocket ID client `stalwart` is public and uses PKCE.
Its callback is `https://stalwart.winstead.io/admin/oauth/callback`. The Flux app creates it.
In Stalwart, set up two things:

1. Add an OIDC directory that points to the Pocket ID issuer. The WebUI finds the identity provider from this directory.
2. Open the Application object `Stalwart Web Interface`. Set the OAuth client ID to `stalwart` and the OAuth scopes to `profile email`.

Not verified: I did not check the menu path of the Application object in the WebUI.
I did not test the Pocket ID sign-in.

### 1.5 Database notes

- The link to Postgres uses TLS but does not check the server certificate (`allowInvalidCerts`).
  CNPG signs the certificate with its own CA. Stalwart has no setting for a CA file, so it cannot check that CA.
  The traffic stays inside the cluster.
- `/var/lib/stalwart` is an empty directory that the pod loses at each restart. Stalwart keeps no state in it.
- To change the data store, edit `config.json` in the HelmRelease. Stalwart restarts on the change.

## 2. Get the account ID and the inbox ID

Get the account ID. Use the Worker account and its password:

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

## 5. Set the secrets and deploy the Worker

Run these commands in `workers/pkg-mail-ingest`:

```sh
npx wrangler secret put STALWART_USER             # the Worker account, for example packages@pkg.winstead.io
npx wrangler secret put STALWART_PASSWORD         # the app password for the Worker
npx wrangler secret put CF_ACCESS_CLIENT_ID
npx wrangler secret put CF_ACCESS_CLIENT_SECRET
npx wrangler deploy
```

Before you deploy, replace `REPLACE_ME` in `wrangler.toml`: `ACCOUNT_ID`, `INBOX_ID`, and `FALLBACK_ADDR`.

## 6. Set up Email Routing

1. In the Cloudflare dashboard, open the zone `winstead.io`. Go to Email > Email Routing.
2. Enable Email Routing for the subdomain `pkg.winstead.io`. Add the DNS records that Cloudflare shows.
3. Go to Destination addresses. Add the `FALLBACK_ADDR` address. Open the verification email and confirm it.
4. Add a custom address rule:
   - Custom address: `packages@pkg.winstead.io`
   - Action: Send to a Worker
   - Destination: `pkg-mail-ingest`

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
