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

exec "$@"
