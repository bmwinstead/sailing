# Pipeline step body (see pipeline.tf). Buildkite runs this under /bin/sh, so
# keep it POSIX. Checkout is done by the `entire` plugin before this runs.
set -eu

# CLI version must match the engine chart in kubernetes/apps/buildkite/dagger-engine.
curl -fsSLo /tmp/dagger-install.sh https://dl.dagger.io/dagger/install.sh
DAGGER_VERSION="$DAGGER_VERSION" BIN_DIR=/usr/local/bin sh /tmp/dagger-install.sh

export _EXPERIMENTAL_DAGGER_RUNNER_HOST="$DAGGER_ENGINE_HOST"
dagger check

# Publish ./kubernetes as a Flux OCI artifact on main. The Buildkite registry
# then fires package.created, which makes Flux reconcile (see
# kubernetes/apps/flux-system/performance). Auth is a short-lived OIDC token
# allowed by oidc_policy in registry.tf.
if [ "${BUILDKITE_BRANCH:-}" = main ]; then
  BK_OIDC_TOKEN="$(buildkite-agent oidc request-token --audience https://packages.buildkite.com/winstead-io/sailing --lifetime 300)"
  export BK_OIDC_TOKEN
  dagger call performance publish --token=env://BK_OIDC_TOKEN --revision="$BUILDKITE_COMMIT"
fi
