#!/bin/bash
# Pipeline step body (see pipeline.tf). Checkout is done by the `entire`
# Buildkite plugin before this runs, so the workdir is already the repo.
set -euo pipefail


# CLI version must match the engine chart in kubernetes/apps/buildkite/dagger-engine.
curl -fsSL https://dl.dagger.io/dagger/install.sh \
  | DAGGER_VERSION="$DAGGER_VERSION" BIN_DIR=/usr/local/bin sh

export _EXPERIMENTAL_DAGGER_RUNNER_HOST="$DAGGER_ENGINE_HOST"
dagger check
