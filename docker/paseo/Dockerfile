# Paseo daemon + the same tooling as the claude-code devbox image, so agents
# started from Paseo (terminal/mobile) get the same environment as `just`
# targets on a laptop. Tool versions are pinned once, in docker/claude-code;
# this image copies the binaries out of it rather than repeating the downloads.
# ponytail: rebuild this image when docker/claude-code changes (no cross-image
# trigger yet); add one if the two drift.
ARG PASEO_TAG=latest
FROM ghcr.io/bmwinstead/claude-code-devbox:latest AS devbox

FROM ghcr.io/getpaseo/paseo:${PASEO_TAG}

# Stay root: the Paseo entrypoint uses root for first-run volume setup, then
# drops the daemon and agents to the `paseo` user (uid/gid 1000).
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      jq less openssh-client python3 vim-tiny \
    && rm -rf /var/lib/apt/lists/*

COPY --from=devbox /usr/local/bin/kubectl /usr/local/bin/talosctl /usr/local/bin/sops \
     /usr/local/bin/age /usr/local/bin/age-keygen /usr/local/bin/just /usr/local/bin/gh \
     /usr/local/bin/
COPY --from=devbox /usr/local/libexec/gh-extensions /usr/local/libexec/gh-extensions

# Entire CLI + git-remote-entire, for cloning entire:// repos (e.g. performance).
# `entire auth login` is still interactive; credentials live on the home PVC.
ARG ENTIRE_VERSION=0.13.1
ARG TARGETARCH
RUN cd /tmp \
    && curl -fsSLO "https://github.com/entireio/cli/releases/download/v${ENTIRE_VERSION}/entire_linux_${TARGETARCH}.tar.gz" \
    && curl -fsSLO "https://github.com/entireio/cli/releases/download/v${ENTIRE_VERSION}/checksums.txt" \
    && grep " entire_linux_${TARGETARCH}.tar.gz\$" checksums.txt | sha256sum -c - \
    && tar -xzf "entire_linux_${TARGETARCH}.tar.gz" -C /usr/local/bin entire git-remote-entire \
    && rm -f /tmp/entire_linux_* /tmp/checksums.txt

# mise, so each repo's mise.toml gives agents its own pinned toolchain (Go,
# Node, linters). Tools install into ~/.local/share/mise on the home PVC, and
# the shims dir on PATH makes them visible to agent shells with no activation.
ARG MISE_VERSION=2026.11.6
RUN case "${TARGETARCH}" in amd64) MISE_ARCH=x64 ;; *) MISE_ARCH="${TARGETARCH}" ;; esac \
    && cd /tmp \
    && curl -fsSLO "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${MISE_ARCH}" \
    && curl -fsSLO "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/SHASUMS256.txt" \
    && grep " ./mise-v${MISE_VERSION}-linux-${MISE_ARCH}\$" SHASUMS256.txt | sha256sum -c - \
    && install -m 755 "mise-v${MISE_VERSION}-linux-${MISE_ARCH}" /usr/local/bin/mise \
    && rm -f /tmp/mise-v* /tmp/SHASUMS256.txt
ENV PATH=/home/paseo/.local/share/mise/shims:$PATH

# The base image ships no agent CLIs (see paseo.sh/docs/docker).
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# Wrap Paseo's entrypoint (tini -> paseo-docker-entrypoint) with the in-cluster
# kubeconfig + GitHub App wiring from the old claude-code devbox.
COPY --chmod=755 devbox-init.sh /usr/local/bin/devbox-init.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/devbox-init.sh"]
