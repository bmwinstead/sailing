set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just buildkite -l

[doc('Initialize the OpenTofu working directory')]
[group('buildkite')]
init:
    tofu init

[doc('Preview changes to the Buildkite cluster/queue/agent token')]
[group('buildkite')]
plan:
    tofu plan

[doc('Apply changes to the Buildkite cluster/queue/agent token')]
[group('buildkite')]
apply:
    tofu apply

[doc('SOPS-encrypt the current agent token into the k8s Secret')]
[group('buildkite')]
[script]
sync-secret:
    token="$(tofu output -raw agent_token)"
    secret_path="../kubernetes/apps/buildkite/agent-stack-k8s/app/secret-agent-token.sops.yaml"
    cat <<SECRET | sops --filename-override "$secret_path" --encrypt /dev/stdin > "$secret_path"
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: buildkite-agent-token
      namespace: buildkite
    stringData:
      BUILDKITE_AGENT_TOKEN: $token
    SECRET
    just log info "Encrypted secret written" path "$secret_path"
    just log info "Next: add './secret-agent-token.sops.yaml' to app/kustomization.yaml's resources, commit, then 'just kube reconcile'"
