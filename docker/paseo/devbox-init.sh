#!/bin/bash
set -euo pipefail

# Same in-cluster wiring as docker/claude-code/entrypoint.sh (kubeconfig from the
# pod's ServiceAccount token, gh-app-auth git credentials), but $HOME-relative
# since Paseo's home is /home/paseo, then hands off to Paseo's own entrypoint.
# Expects to run as the non-root `paseo` user (the Deployment sets runAsUser 1000).

SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
if [ -f "$SA_DIR/token" ] && [ ! -f "$HOME/.kube/config" ]; then
  mkdir -p "$HOME/.kube"
  kubectl config set-cluster in-cluster \
    --server="https://kubernetes.default.svc" \
    --certificate-authority="$SA_DIR/ca.crt" >/dev/null
  kubectl config set-credentials sa --token="placeholder" >/dev/null
  # tokenFile (not the value) so kubectl follows kubelet's token rotation.
  sed -i "s#token: placeholder#tokenFile: $SA_DIR/token#" "$HOME/.kube/config"
  kubectl config set-context in-cluster --cluster=in-cluster --user=sa --namespace=default >/dev/null
  kubectl config use-context in-cluster >/dev/null
fi

# gh-app-auth lives outside $HOME in the image (the home PVC masks $HOME).
GH_APP_AUTH_DIR="$HOME/.local/share/gh/extensions/gh-app-auth"
if [ ! -e "$GH_APP_AUTH_DIR" ]; then
  mkdir -p "$(dirname "$GH_APP_AUTH_DIR")"
  ln -s /usr/local/libexec/gh-extensions/gh-app-auth "$GH_APP_AUTH_DIR"
fi

# gh-app-auth refuses a key with group/other read bits and the secret mount is
# read-only 0644, so copy it to a 0600 path each start.
GH_APP_KEY_SRC="$HOME/.github-app/private-key.pem"
if [ -f "$GH_APP_KEY_SRC" ] && [ -n "${GH_APP_ID:-}" ] && [ -n "${GH_APP_PRIVATE_KEY_PATH:-}" ]; then
  mkdir -p "$(dirname "$GH_APP_PRIVATE_KEY_PATH")"
  install -m 600 "$GH_APP_KEY_SRC" "$GH_APP_PRIVATE_KEY_PATH"
  gh app-auth gitconfig --sync --auto >/dev/null

  # Attribute commits to the bot, not whoever is logged into `claude`.
  git config --global user.name "${GH_APP_BOT_NAME:-atmophytes[bot]}"
  git config --global user.email "${GH_APP_BOT_EMAIL:-331837616+atmophytes[bot]@users.noreply.github.com}"
fi

exec /usr/local/bin/paseo-docker-entrypoint "$@"
