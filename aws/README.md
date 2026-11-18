# aws

OpenTofu module for the AWS account `338208726210`. It manages two things:

- The S3 bucket `winstead-tfstate` (region `us-east-2`). It stores the state of this module.
- The KMS key `5f27f89c-2f4e-49c9-9263-63596049bde5`. SOPS uses it.

The module does not manage the object `state` in the bucket. That object is the state of the retired `home` repo. Do not delete it. Do not use that key.

The module creates no IAM user, role or CI identity.

## Prerequisites

1. Install the tools with `mise install`.
2. Install the AWS CLI. The recipes use it to find out what already exists.
3. Sign in. Run `aws login`, or run `aws sso login --profile <profile>`.
4. For an SSO profile, set the profile. In bash, run `export AWS_PROFILE=<profile>`. In fish, run `set -gx AWS_PROFILE <profile>`.
5. Make sure you use account `338208726210`. The provider and the recipes stop on any other account.

You need permission to read and write the bucket, and to manage the KMS key.

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

Step 2 does this:

1. It copies `terraform.tfstate` to `terraform.tfstate.bootstrap-backup`.
2. It deletes `backend_override.tf` and `imports.tf`.
3. It runs `tofu init -migrate-state`. This moves the state to `aws/terraform.tfstate` in the bucket.
4. It runs `just aws check`.

## Check success

Run `just aws check`. It runs `tofu plan -detailed-exitcode`.

- Exit code 0 and `No changes` mean success.
- Exit code 2 means the plan has changes. Read the plan. After a correct import, no change is expected.
- Any other exit code means an error.

To check that the state is in S3, run:

```sh
aws s3api head-object --bucket winstead-tfstate --key aws/terraform.tfstate --region us-east-2
```

After this, run `just aws init`, `just aws plan` and `just aws apply` as usual. The S3 backend uses a lock file (`use_lockfile = true`). It does not need a DynamoDB table.

## Undo a failed step

- **Step 1 failed before the apply finished.** Run `just aws bootstrap-local` again. It only imports the objects that are not in the state. It does not create an object twice.
- **Step 1 failed and you want to start over before anything was created.** Run `rm -rf .terraform backend_override.tf imports.tf` in the `aws/` directory. Then run step 1 again.
- **Step 2 failed.** Run `just aws bootstrap-migrate` again. The local state stays in `terraform.tfstate` and in `terraform.tfstate.bootstrap-backup`.
- **The state in S3 is wrong.** The bucket keeps old versions of every object. Restore an older version of `aws/terraform.tfstate`. Then run `just aws check`.
- **Step 1 refuses to run because the state exists in S3.** The bootstrap is already done. Run `just aws init`.

`prevent_destroy` is set on the bucket and on the key. `tofu destroy` stops with an error. Do not remove `prevent_destroy` without a reason.
