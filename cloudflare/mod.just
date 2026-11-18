set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just cloudflare -l

[doc('Initialize the OpenTofu working directory')]
[group('cloudflare')]
init:
    tofu init

[doc('Preview changes to the R2 bucket and its API token')]
[group('cloudflare')]
plan:
    tofu plan

[doc('Apply changes to the R2 bucket and its API token')]
[group('cloudflare')]
apply:
    tofu apply

[doc('SOPS-encrypt the R2 S3 credentials into the k8s Secret')]
[group('cloudflare')]
[script]
sync-secret:
    access_key_id="$(tofu output -raw access_key_id)"
    secret_access_key="$(tofu output -raw secret_access_key)"
    secret_path="../kubernetes/apps/default/home-assistant/app/secret-r2.sops.yaml"
    cat <<SECRET | sops --filename-override "$secret_path" --encrypt /dev/stdin > "$secret_path"
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: cnpg-r2-credentials
      namespace: default
    stringData:
      ACCESS_KEY_ID: $access_key_id
      ACCESS_SECRET_KEY: $secret_access_key
    SECRET
    just log info "Encrypted secret written" path "$secret_path"
