terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }

    buildkite = {
      source  = "buildkite/buildkite"
      version = "1.48.0"
    }
  }
}
