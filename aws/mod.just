set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

state_key := 'aws/terraform.tfstate'

[private]
default:
    just aws -l

[doc('Initialize the OpenTofu working directory with the S3 backend')]
[group('aws')]
init:
    tofu init

[doc('Preview changes to the state bucket and the SOPS KMS key')]
[group('aws')]
plan:
    tofu plan

[doc('Apply changes to the state bucket and the SOPS KMS key')]
[group('aws')]
apply:
    tofu apply

[doc('Exit 0 if the live account matches the code, exit 2 if not')]
[group('aws')]
[script]
check:
    rc=0
    tofu plan -detailed-exitcode -lock-timeout=30s || rc=$?
    case "$rc" in
      0) just log info "No changes. The code matches the live account." ;;
      2) just log warn "The plan has changes. Read the plan above." ;;
    esac
    exit "$rc"

[doc('Bootstrap step 1: use local state, import or create the bucket and key')]
[group('aws')]
[script]
bootstrap-local:
    command -v aws >/dev/null || { just log error "The aws CLI is not installed"; exit 1; }
    cat > backend_override.tf <<'OVERRIDE'
    # Written by "just aws bootstrap-local". Replaces the S3 backend. Not committed.
    terraform {
      backend "local" {
        path = "terraform.tfstate"
      }
    }
    OVERRIDE
    tofu init -reconfigure
    var() { echo "var.$1" | tofu console | tr -d '"'; }
    account="$(var account_id)"
    region="$(var region)"
    bucket="$(var bucket_name)"
    key_id="$(var kms_key_id)"
    caller="$(aws sts get-caller-identity --query Account --output text)"
    [ "$caller" = "$account" ] || { just log error "Signed in to account $caller, not $account"; exit 1; }
    # Prints "yes" if the command works, "no" if the object is missing. Any other error stops the script.
    exists() {
      if err="$("$@" 2>&1 >/dev/null)"; then echo yes; return 0; fi
      case "$err" in
        *"Not Found"* | *NotFoundException* | *"(404)"*) echo no ;;
        *) printf '%s\n' "$err" >&2; return 1 ;;
      esac
    }
    bucket_exists="$(exists aws s3api head-bucket --bucket "$bucket" --region "$region")"
    key_exists="$(exists aws kms describe-key --key-id "$key_id" --region "$region")"
    if [ "$bucket_exists" = yes ] && [ "$(exists aws s3api head-object --bucket "$bucket" --key "{{ state_key }}" --region "$region")" = yes ]; then
      just log error "State exists in S3 at {{ state_key }}. Run 'just aws init' instead."
      exit 1
    fi
    managed="$(tofu state list)"
    : > imports.tf
    add_import() {
      if [ "$3" = yes ] && ! grep -qx "$1" <<<"$managed"; then
        printf 'import {\n  to = %s\n  id = var.%s\n}\n\n' "$1" "$2" >> imports.tf
        just log info "Will import" resource "$1"
      fi
    }
    add_import aws_s3_bucket.tfstate bucket_name "$bucket_exists"
    add_import aws_s3_bucket_versioning.tfstate bucket_name "$bucket_exists"
    add_import aws_s3_bucket_server_side_encryption_configuration.tfstate bucket_name "$bucket_exists"
    add_import aws_s3_bucket_public_access_block.tfstate bucket_name "$bucket_exists"
    add_import aws_s3_bucket_ownership_controls.tfstate bucket_name "$bucket_exists"
    add_import aws_kms_key.sops kms_key_id "$key_exists"
    tofu apply
    just log info "Next: just aws bootstrap-migrate"

[doc('Bootstrap step 2: move the local state into the S3 backend and check it')]
[group('aws')]
[script]
bootstrap-migrate:
    [ -f terraform.tfstate ] || { just log error "No local state. Run 'just aws bootstrap-local' first."; exit 1; }
    cp -p terraform.tfstate terraform.tfstate.bootstrap-backup
    rm -f backend_override.tf imports.tf
    tofu init -migrate-state
    just aws check

[doc('Run both bootstrap steps')]
[group('aws')]
bootstrap: bootstrap-local bootstrap-migrate
