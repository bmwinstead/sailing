# aws

OpenTofu module for the AWS account `338208726210`. It manages these things:

- The S3 bucket `winstead-tfstate` (region `us-east-2`). It stores the OpenTofu state of the `aws/` and `cloudflare/` modules.
- The KMS key `5f27f89c-2f4e-49c9-9263-63596049bde5` and its alias `alias/sailing`. One key encrypts three things: the state bucket, SSM SecureString parameters and SOPS files.
- Three IAM users with access keys: `sailing-tofu`, `sailing-flux-sops` and `sailing-stalwart`.

The module does not manage the object `state` in the bucket. That object is the state of the retired `home` repo. Do not delete it. Do not use that key.

The module does not manage the key policy. The key keeps the default policy (the root account has `kms:*`). So IAM policies on users grant access to the key.

The `aws/` module stays on the laptop. Never give its credentials, or its state, to the in-cluster runner.

## IAM users

The access keys and the secrets are sensitive outputs of this module. Read one with `tofu output -raw <name>`. The module writes no Kubernetes manifest and no secret file. The recipe `just aws sync-stalwart-secret` writes the SOPS file for `sailing-stalwart`.

### `sailing-tofu`

The in-cluster OpenTofu runner (Flux tofu-controller) uses this user. It can:

- Read the SSM parameters under `/sailing/tofu` (`ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParametersByPath`).
- Decrypt with the key (`kms:Decrypt`) only if the encryption context `PARAMETER_ARN` is a parameter under `/sailing/tofu/*`.
- List the bucket only for the prefixes `cloudflare/*` and `buildkite/*`.
- Read, write and delete objects only under `cloudflare/*` and `buildkite/*`. The lock files (`*.tflock`) are in the same prefixes.
- Call `kms:GenerateDataKey` and `kms:Decrypt` on the key only if the encryption context `aws:s3:arn` is the bucket ARN.

It has no access to `aws/*` and none to the key `state`.

The state bucket has S3 Bucket Keys on. With a bucket key, S3 uses the bucket ARN as the encryption context, not the object ARN. So the KMS condition cannot restrict by prefix. The S3 object permissions do the restricting.

The `s3:ListBucket` condition uses `StringLikeIfExists`. A `GetObject` request has no `s3:prefix` key. A plain `StringLike` would make S3 answer 403 and not 404 for a state file that does not exist yet.

### `sailing-flux-sops`

Flux uses this user to decrypt SOPS files. It can:

- Call `kms:Decrypt` on the key only if the encryption context `purpose` is `sops`.
- Call `kms:DescribeKey` on the key. This call has no encryption context, so it has no condition.

This PR does not change `.sops.yaml` or any SOPS file. A later PR moves SOPS from age to KMS. That PR must add the key ARN as a KMS recipient in `.sops.yaml` with the context map `purpose: sops`. It must also re-encrypt the SOPS files. Until then, `sailing-flux-sops` cannot decrypt anything.

### `sailing-stalwart`

The Job `stalwart-pkg-credentials` in the cluster uses this user. The Job makes the app passwords of the mailbox `packages@pkg.winstead.io` and writes them to SSM. The user can:

- Call `ssm:PutParameter` and `ssm:GetParameter` only on the parameters `/sailing/tofu/pkg-mail-*`.
- Call `kms:Encrypt` and `kms:GenerateDataKey` on the key only if the encryption context `PARAMETER_ARN` is a parameter under `/sailing/tofu/pkg-mail-*`. SSM uses `kms:Encrypt` for a standard SecureString and `kms:GenerateDataKey` for an advanced one.

It has no `kms:Decrypt`. The Job uses `ssm:GetParameter` without decryption only to find out if a parameter exists. It cannot read a secret back.

The Job reads the access key from the Secret `stalwart-aws-credentials` in the namespace `default`. Write that Secret with `just aws sync-stalwart-secret` (see "Give the access key to Stalwart").

## Prerequisites

1. Install the tools with `mise install`.
2. Install the AWS CLI. The recipes use it to find out what already exists.
3. Sign in. Run `aws login`, or run `aws sso login --profile <profile>`.
4. For an SSO profile, set the profile. In bash, run `export AWS_PROFILE=<profile>`. In fish, run `set -gx AWS_PROFILE <profile>`.
5. Make sure you use account `338208726210`. The provider and the recipes stop on any other account.

You need permission to manage the bucket, the key, the alias and IAM users.

## Bootstrap

The state bucket is managed by this module, and the module stores its state in the bucket. So the first run uses local state. The second run moves the state into S3.

Run these commands from the repo root. They are the same in bash and fish.

1. `just aws bootstrap-local`
2. Read the plan. Type `yes` to apply.
3. `just aws bootstrap-migrate`
4. Type `yes` when `tofu` asks to copy the state to S3.

`just aws bootstrap` runs both steps in order.

Step 1 does this:

1. It writes `backend_override.tf`. This file selects the local backend. Git ignores it.
2. It checks if the bucket and the key exist.
3. It writes `imports.tf` with one `import` block for each object that exists and is not in the state yet. Git ignores it.
4. It runs `tofu apply`.

On this account, the bucket and the key exist, so step 1 imports them. On an empty account, step 1 creates them. A bucket that exists with a partial configuration is not supported.

### Expected plan in step 1 on this account

The live bucket uses SSE-S3 (`AES256`) and the live key has an old description. The code changes both on purpose. The plan must show 6 imports and these changes, and no other change:

- `aws_s3_bucket_server_side_encryption_configuration.tfstate` changes in place. The algorithm changes from `AES256` to `aws:kms` with the key ARN, and `bucket_key_enabled` changes from `false` to `true`. Old objects keep their encryption. New objects use the key.
- `aws_kms_key.sops` changes in place. Only the description changes.
- `aws_kms_alias.sailing` is created.
- Three IAM users, three user policies and three access keys are created.

Stop and read if the plan shows anything else, for example a replace or a destroy.

Step 2 does this:

1. It copies `terraform.tfstate` to `terraform.tfstate.bootstrap-backup`.
2. It deletes `backend_override.tf` and `imports.tf`.
3. It runs `tofu init -migrate-state`. This moves the state to `aws/terraform.tfstate` in the bucket. The backend uses the key ARN in `backend.tf`.
4. It runs `just aws check`.
5. If the check passes, it deletes the local state files. They hold the IAM secret access keys in plain text.

## Check success

Run `just aws check`. It runs `tofu plan -detailed-exitcode`.

- Exit code 0 and `No changes` mean success. After the bootstrap, expect this result.
- Exit code 2 means the plan has changes. Read the plan.
- Any other exit code means an error.

To check that the state is in S3, run:

```sh
aws s3api head-object --bucket winstead-tfstate --key aws/terraform.tfstate --region us-east-2
```

The answer must show `"ServerSideEncryption": "aws:kms"` and the key ARN.

After this, run `just aws init`, `just aws plan` and `just aws apply` as usual. The S3 backend uses a lock file (`use_lockfile = true`). It does not need a DynamoDB table.

## Store a secret for the runner

`just aws put-secret <name>` stores a SecureString parameter at `/sailing/tofu/<name>`. It encrypts the value with `alias/sailing`. It overwrites an existing parameter. It refuses an empty value.

The recipe reads the value from a hidden prompt, or from stdin if stdin is not a terminal. The value is not in the command line, not in the shell history and not in the recipe output. The recipe needs `just aws init` to be done, because it reads the region, the alias and the path from the module outputs.

```sh
just aws put-secret cloudflare-api-token
```

To read the value from a file, run:

```sh
just aws put-secret cloudflare-api-token < token.txt
```

The name can use letters, digits, dot, underscore and dash. Stdin input loses trailing newlines.

## Give the access key to Stalwart

`just aws sync-stalwart-secret` reads the `sailing-stalwart` access key and the region from the module outputs. It encrypts them with SOPS into `kubernetes/apps/default/stalwart/config/aws-credentials.sops.yaml`. The Secret is `stalwart-aws-credentials` with the keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`.

CAUTION: The Flux Kustomization `stalwart-config` lists this file. If the file is not in git, Flux cannot build `stalwart-config`, and the Stalwart settings do not apply. Commit the file before you merge the change that adds the Job, or in the same change.

1. Run `just aws apply`. The plan creates `sailing-stalwart`, its policy and its access key.
2. Run `just aws sync-stalwart-secret`.
3. Commit `kubernetes/apps/default/stalwart/config/aws-credentials.sops.yaml`.
4. Merge. Flux runs the Job. See `workers/pkg-mail-ingest/README.md` for the parameters that the Job writes.

## Order of operations for the owner

1. Run `just aws plan`. Read the plan. Check the bucket encryption change, the new alias and the new users. On this account, do the bootstrap above instead of a plain `plan`.
2. Run `just aws apply` (or finish the bootstrap).
3. Run `just aws put-secret cloudflare-api-token`.
4. Run the `cloudflare/` module. See the steps at the top of `cloudflare/provider.tf`.

## Undo a failed step

- **Step 1 failed before the apply finished.** Run `just aws bootstrap-local` again. It only imports the objects that are not in the state. It does not create an object twice.
- **Step 1 failed and you want to start over before anything was created.** Run `rm -rf .terraform backend_override.tf imports.tf` in the `aws/` directory. Then run step 1 again.
- **Step 2 failed.** Run `just aws bootstrap-migrate` again. The local state stays in `terraform.tfstate` and in `terraform.tfstate.bootstrap-backup`.
- **The check in step 2 shows changes.** The recipe keeps the local state files. Read the plan. Delete the local files when the state in S3 is correct: `rm -f terraform.tfstate terraform.tfstate.backup terraform.tfstate.bootstrap-backup`.
- **The state in S3 is wrong.** The bucket keeps old versions of every object. Restore an older version of `aws/terraform.tfstate`. Then run `just aws check`.
- **Step 1 refuses to run because the state exists in S3.** The bootstrap is already done. Run `just aws init`.
- **An IAM access key leaked.** Run `tofu apply -replace=aws_iam_access_key.tofu` (or `.flux_sops` or `.stalwart`) in `aws/`. Then give the new key to its user. For `.stalwart`, run `just aws sync-stalwart-secret` and commit the file.

`prevent_destroy` is set on the bucket and on the key. `tofu destroy` stops with an error. Do not remove `prevent_destroy` without a reason.
