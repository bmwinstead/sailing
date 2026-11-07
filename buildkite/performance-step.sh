# Pipeline step body (see pipeline.tf). Buildkite runs this under /bin/sh, so
# keep it POSIX. Checkout is done by the `entire` plugin before this runs.
set -eu

# CLI version must match the engine chart in kubernetes/apps/buildkite/dagger-engine.
curl -fsSLo /tmp/dagger-install.sh https://dl.dagger.io/dagger/install.sh
DAGGER_VERSION="$DAGGER_VERSION" BIN_DIR=/usr/local/bin sh /tmp/dagger-install.sh

export _EXPERIMENTAL_DAGGER_RUNNER_HOST="$DAGGER_ENGINE_HOST"
dagger check
