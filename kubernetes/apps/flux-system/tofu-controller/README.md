# flux-system: tofu-controller

- The Flux Kustomization `tofu-controller` installs the tofu-controller chart. The chart installs the controller and the `Terraform` CRD.
- The Flux Kustomization `tofu-controller-terraform` holds the `Terraform` objects `cloudflare` and `buildkite`. It depends on `tofu-controller`, so the CRD exists first.
- Each `Terraform` object runs the module at `./cloudflare` or `./buildkite` from the GitRepository `flux-system` one time each hour.
- The modules keep their own S3 backend in `backend.tf` (`backendConfig.disable: true`).
- There is no `Terraform` object for `aws/`. That module stays on the laptop.
- The runner pods get their environment from the Secret `tofu-credentials` (`app/secret-credentials.sops.yaml`). It has the keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` and `account_id`. The runner reads the AWS keys as environment variables. The `cloudflare` object reads `account_id` through `varsFrom`, because tofu-controller refuses an environment variable named `TF_VAR_*`. The AWS keys are for the IAM user `sailing-tofu` (see `aws/README.md`).
- The runner image `tf-runner:v0.17.0` has OpenTofu 1.12.1. The modules declare 1.13 or later, and the laptop uses 1.13.9 (`.mise.toml`). OpenTofu does not enforce `required_version` in `.tf` files, so 1.12.1 would run the modules without an error. An init container copies OpenTofu 1.13.9 into the runner pod (see `terraform/kustomization.yaml`). Delete it when `tf-runner` has OpenTofu 1.13 or later.
- `approvePlan` is not set, so a human approves each plan.
- `destroyResourcesOnDeletion` is `false`. When you delete a `Terraform` object, the controller does not destroy its resources.

## Read a plan

1. Run `kubectl -n flux-system get terraform`.
2. Read the `STATUS` column of the object:
   - `Plan no changes: <revision>` means that there is nothing to apply.
   - `Plan generated: set approvePlan: "<id>" to approve this plan.` means that a plan waits for approval.
3. Get the ID of the plan that waits:

   ```sh
   kubectl -n flux-system get terraform cloudflare -o jsonpath='{.status.plan.pending}'
   ```

   The ID has the form `plan-refs/heads/main-<first 10 characters of the commit SHA>`.

4. Read the plan text. The runner pod `<name>-tf-runner` writes the plan to its log. The controller deletes the pod after each run. Alloy sends the log to Loki. In Grafana Explore, use this query:

   ```logql
   {namespace="flux-system", pod="cloudflare-tf-runner"}
   ```

   The controller keeps no readable copy of the plan, because the backend is disabled. You can also run `just cloudflare plan` on the laptop at the same commit.

## Approve a plan

CAUTION: Do not approve with a Git commit. A commit to `main` changes the source revision. The controller then makes a new plan with a new ID, and your approval does not match it. See [flux-iac/tofu-controller#1878](https://github.com/flux-iac/tofu-controller/issues/1878).

1. Write down the pending plan ID from step 3 of "Read a plan". Read the plan for that ID.
2. On the laptop, set the ID on the object in the cluster. Use the field manager `tofu-approval`:

   ```sh
   kubectl -n flux-system patch terraform cloudflare --type merge \
     --field-manager tofu-approval \
     -p '{"spec":{"approvePlan":"<plan-id>"}}'
   ```

   Do not use `kubectl edit` or a `kubectl patch` without `--field-manager`. Flux takes ownership of fields from managers whose name starts with `kubectl`, and then deletes `approvePlan` at its next run.

3. The controller makes the plan again at the same revision. If the ID is the same, it applies.
4. Run `kubectl -n flux-system get terraform cloudflare`. The `STATUS` column starts with `Applied successfully` after the apply.
5. If a commit reached `main` between step 1 and step 3, the ID changes and the controller waits. Start again at step 1.

The backend is disabled, so the controller does not save a plan file. The apply runs `tofu apply` on the configuration of the approved revision and computes the changes again at that time. An approval accepts a revision, not a byte-exact plan.
