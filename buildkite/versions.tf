terraform {
  required_version = ">= 1.13.0"

  required_providers {
    buildkite = {
      source  = "buildkite/buildkite"
      version = "1.47.0"
    }
  }
}
