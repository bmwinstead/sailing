# auth: Pocket ID with the pocket-id-operator

- The `pocket-id` Flux Kustomization installs the HelmRelease `pocket-id-operator`.
- The chart installs the operator, the CRDs, and the `PocketIDInstance` named `id`.
- The operator starts Pocket ID, a Longhorn volume, and the HTTPRoute for `id.${SECRET_DOMAIN}`.
- The operator calls Pocket ID with the API key in the Secret `id-static-api-key`.
- The encryption key is in the Secret `pocket-id-secret`.
- The `PocketIDUserGroup` `admins` is in the HelmRelease. Add users to it in the UI.

## Add an app client

1. Put a `PocketIDOIDCClient` in the namespace of the app.
2. Make the Flux Kustomization of the app `dependsOn` `pocket-id`, so the CRDs exist first.
3. Read `client_id` and `client_secret` from the Secret `<client>-oidc-credentials`.

```yaml
apiVersion: pocketid.internal/v1alpha1
kind: PocketIDOIDCClient
metadata:
  name: grafana
spec:
  callbackUrls:
    - https://grafana.${SECRET_DOMAIN}/login/generic_oauth
  pkceEnabled: true
  allowedUserGroups:
    - name: admins
      namespace: auth
```

## Examples

- Grafana is a native OIDC client. See `kubernetes/apps/observability/grafana/instance/oidcclient.yaml`.
- SABnzbd uses an Envoy Gateway SecurityPolicy. See `kubernetes/apps/default/sabnzbd/app/oidcclient.yaml`.
- Both clients rename the Secret keys with `spec.secret`, because Envoy needs `client-id` and `client-secret`.
- Both Flux Kustomizations `dependsOn` `pocket-id` in the namespace `auth`.
