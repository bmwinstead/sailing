# Claude Code devbox: an in-cluster shell with the tooling this repo's own
# CLAUDE.md commands need (git, kubectl, talosctl, sops, age, just, gh) plus
# the Claude Code CLI itself. Pin versions to match the cluster (kubectl) and
# this repo's toolchain (mise.toml) so `just` targets behave the same in here
# as they do on a laptop.
FROM node:24-bookworm-slim

ARG KUBECTL_VERSION=v1.36.1
ARG TALOSCTL_VERSION=v1.9.4
ARG SOPS_VERSION=3.9.4
ARG AGE_VERSION=1.2.1
ARG JUST_VERSION=1.38.0
ARG GH_VERSION=2.63.2
ARG GH_APP_AUTH_VERSION=0.0.8

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less openssh-client python3 tar unzip vim-tiny \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSLo /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOSCTL_VERSION}/talosctl-linux-${ARCH}" \
    && chmod +x /usr/local/bin/talosctl \
    && curl -fsSLo /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${ARCH}" \
    && chmod +x /usr/local/bin/sops \
    && curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen \
    && curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin just \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_${ARCH}/bin/gh" \
    && mkdir -p /usr/local/libexec/gh-extensions/gh-app-auth \
    && curl -fsSLo /usr/local/libexec/gh-extensions/gh-app-auth/gh-app-auth \
         "https://github.com/AmadeusITGroup/gh-app-auth/releases/download/v${GH_APP_AUTH_VERSION}/linux-${ARCH}" \
    && chmod +x /usr/local/libexec/gh-extensions/gh-app-auth/gh-app-auth

RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# node:22 already ships a `node` user at uid/gid 1000 — reuse it rather than
# creating a conflicting one (matches the uid this repo's other devbox image,
# openclaw-team, also relies on).
USER node
WORKDIR /home/node

# Generates ~/.kube/config from the pod's projected ServiceAccount token on
# every shell start, so `kubectl` just works with whatever RBAC the
# ServiceAccount has — no kubeconfig baked into the image or mounted as a secret.
COPY --chown=node:node --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
