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
- `../../kubernetes/apps/default/stalwart`: the Stalwart deployment (Flux).

## 1. Start Stalwart and do the first-run setup

Flux deploys Stalwart from `kubernetes/apps/default/stalwart`. The image is Stalwart v1.1.1.
The first start has no `config.json`. Stalwart then runs in bootstrap mode.
Bootstrap mode serves only the setup wizard on port 8080.

1. Wait until the pod is ready:
   `kubectl --kubeconfig=kubeconfig -n default get pods -l app.kubernetes.io/name=stalwart`
2. Find the temporary admin password in the logs:
   `kubectl --kubeconfig=kubeconfig -n default logs deploy/stalwart | grep -A8 'bootstrap mode'`
   The password changes at each bootstrap start. Use the newest block.
3. Open the wizard:
   `kubectl --kubeconfig=kubeconfig -n default port-forward svc/stalwart 8080:8080`
   Then open `http://localhost:8080/admin`. Sign in as `admin`.
4. Finish the wizard. Use the internal directory and the domain `pkg.winstead.io`.
   The wizard writes `config.json` to `/etc/stalwart`. It shows the password of `admin@pkg.winstead.io` once. Save it.
5. Restart the pod. Stalwart stays in bootstrap mode until a restart:
   `kubectl --kubeconfig=kubeconfig -n default rollout restart deploy/stalwart`
6. Open the admin UI again with the port-forward. Sign in with the admin account from the wizard.
   If the sign-in page fails, the UI needs its configured HTTPS hostname. Use the JMAP calls in step 2 with `curl` instead.
7. Create the account `packages@pkg.winstead.io`.
8. Create two app passwords for that account if Stalwart supports them. One is for the Worker. One is for Home Assistant.
   If Stalwart does not support them, use the account password.
9. Disable the SMTP, POP3, and ManageSieve listeners. Keep the HTTP listener on port 8080 and the IMAPS listener on port 993.
   The Kubernetes Service exposes only these two ports. Disable the other listeners to keep the config clean.

Notes:

- Do not set `STALWART_RECOVERY_ADMIN` in the manifest. It would put a fixed credential in git.
  The temporary password in the logs is enough for one setup.
- Check that the HTTP listener on port 8080 still exists after the restart. The Kubernetes probes and the tunnel use it.

## 2. Get the account ID and the inbox ID

Open the port-forward:

```sh
kubectl --kubeconfig=kubeconfig -n default port-forward svc/stalwart 8080:8080
```

Get the account ID. Use the Worker account and its password:

```sh
curl -s -u 'packages@pkg.winstead.io:PASSWORD' http://localhost:8080/jmap/session | jq '.primaryAccounts'
```

Copy the value of `urn:ietf:params:jmap:mail`. This value is `ACCOUNT_ID`.

Get the inbox ID:

```sh
curl -s -u 'packages@pkg.winstead.io:PASSWORD' http://localhost:8080/jmap/ \
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
- Exclude the Stalwart data volume from backups, or decide how to keep it.
- Add a Home Assistant alert when no mail arrives for several days.
