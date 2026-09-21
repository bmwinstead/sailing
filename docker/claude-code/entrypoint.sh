#!/bin/bash
set -euo pipefail

# Build an in-cluster kubeconfig from the pod's mounted ServiceAccount token.
# kubectl has no native "just use in-cluster config" mode (that's a client-go
# thing), so this is the standard workaround.
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
if [ -f "$SA_DIR/token" ] && [ ! -f "$HOME/.kube/config" ]; then
  mkdir -p "$HOME/.kube"
  kubectl config set-cluster in-cluster \
    --server="https://kubernetes.default.svc" \
    --certificate-authority="$SA_DIR/ca.crt" >/dev/null
  kubectl config set-credentials sa --token="placeholder" >/dev/null
  # Point at the token file directly (not the value above) so kubectl picks up
  # kubelet's automatic token rotation instead of using a stale copy.
  sed -i "s#token: placeholder#tokenFile: $SA_DIR/token#" "$HOME/.kube/config"
  kubectl config set-context in-cluster --cluster=in-cluster --user=sa --namespace=default >/dev/null
  kubectl config use-context in-cluster >/dev/null
fi

# gh-app-auth is baked into the image at a fixed path (not under $HOME, since
# the home PVC mount masks whatever the image put there). Symlink it into
# gh's extension dir on $HOME each start — cheap and idempotent.
GH_APP_AUTH_DIR="$HOME/.local/share/gh/extensions/gh-app-auth"
if [ ! -e "$GH_APP_AUTH_DIR" ]; then
  mkdir -p "$(dirname "$GH_APP_AUTH_DIR")"
  ln -s /usr/local/libexec/gh-extensions/gh-app-auth "$GH_APP_AUTH_DIR"
fi

# gh-app-auth's auto-mode git credential helper reads GH_APP_ID and
# GH_APP_PRIVATE_KEY_PATH from the environment on every git operation (it
# doesn't persist config from `setup`), and it refuses a key file with
# group/other read bits. The secret volume mount is read-only 0644, so copy
# it to a writable, 0600 path each start before wiring the credential
# helper up — cheap and idempotent.
GH_APP_KEY_SRC=/home/node/.github-app/private-key.pem
if [ -f "$GH_APP_KEY_SRC" ] && [ -n "${GH_APP_ID:-}" ] && [ -n "${GH_APP_PRIVATE_KEY_PATH:-}" ]; then
  mkdir -p "$(dirname "$GH_APP_PRIVATE_KEY_PATH")"
  install -m 600 "$GH_APP_KEY_SRC" "$GH_APP_PRIVATE_KEY_PATH"
  gh app-auth gitconfig --sync --auto >/dev/null
fi

exec "$@"
