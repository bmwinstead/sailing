locals {
  ssm_tofu_arn = "arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.ssm_path_prefix}"

  # State prefixes of the modules that the cluster runner manages. The "aws"
  # prefix and the key "state" are not in this list on purpose.
  runner_state_prefixes = ["cloudflare", "buildkite"]
}

# The in-cluster OpenTofu runner. It reads provider secrets from SSM and keeps
# the state of the cloudflare and buildkite modules.
resource "aws_iam_user" "tofu" {
  name = "sailing-tofu"
}

data "aws_iam_policy_document" "tofu" {
  statement {
    sid       = "ReadTofuParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.ssm_tofu_arn, "${local.ssm_tofu_arn}/*"]
  }

  # SSM SecureString encryption context: key PARAMETER_ARN, value the
  # parameter ARN. Source: AWS Systems Manager User Guide, "AWS KMS encryption
  # for Parameter Store SecureString parameters".
  statement {
    sid       = "DecryptTofuParameters"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.sops.arn]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = ["${local.ssm_tofu_arn}/*"]
    }
  }

  # StringLikeIfExists: a GetObject or HeadObject request has no s3:prefix
  # key. A plain StringLike would then deny it, and S3 would answer 403 and
  # not 404 for a state file that does not exist yet.
  statement {
    sid       = "ListRunnerStatePrefixes"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values   = [for p in local.runner_state_prefixes : "${p}/*"]
    }
  }

  # The lock files (*.tflock) live in the same prefixes as the state files.
  statement {
    sid       = "ReadWriteRunnerState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for p in local.runner_state_prefixes : "${aws_s3_bucket.tfstate.arn}/${p}/*"]
  }

  # The bucket has S3 Bucket Keys on. Then the KMS encryption context
  # aws:s3:arn is the bucket ARN, not the object ARN. Source: Amazon S3 User
  # Guide, "Using server-side encryption with AWS KMS keys (SSE-KMS)" and
  # "Reducing the cost of SSE-KMS with Amazon S3 Bucket Keys".
  # This condition cannot restrict by prefix, because the bucket ARN is the
  # same for every object. The S3 object permissions above do the restricting.
  statement {
    sid       = "UseStateBucketKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.sops.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [aws_s3_bucket.tfstate.arn]
    }
  }
}

resource "aws_iam_user_policy" "tofu" {
  name   = "sailing-tofu"
  user   = aws_iam_user.tofu.name
  policy = data.aws_iam_policy_document.tofu.json
}

resource "aws_iam_access_key" "tofu" {
  user = aws_iam_user.tofu.name
}

# Flux decrypts SOPS files with this user.
resource "aws_iam_user" "flux_sops" {
  name = "sailing-flux-sops"
}

data "aws_iam_policy_document" "flux_sops" {
  # SOPS sets the encryption context from the "context" map of its KMS
  # recipient in .sops.yaml. Use the pair purpose=sops there.
  statement {
    sid       = "DecryptSopsFiles"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.sops.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:purpose"
      values   = ["sops"]
    }
  }

  # DescribeKey has no encryption context. A kms:EncryptionContext condition
  # applies only to cryptographic operations, so this statement has none.
  statement {
    sid       = "DescribeSopsKey"
    actions   = ["kms:DescribeKey"]
    resources = [aws_kms_key.sops.arn]
  }
}

resource "aws_iam_user_policy" "flux_sops" {
  name   = "sailing-flux-sops"
  user   = aws_iam_user.flux_sops.name
  policy = data.aws_iam_policy_document.flux_sops.json
}

resource "aws_iam_access_key" "flux_sops" {
  user = aws_iam_user.flux_sops.name
}
