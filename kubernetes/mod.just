set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just kube -l

[doc('Force Flux to pull in changes from your Git repository')]
[group('kube')]
reconcile:
    flux --namespace flux-system reconcile kustomization flux-system --with-source

[doc('Edit the centralized app secrets file')]
[group('kube')]
edit-secrets:
    cd {{ source_directory() }}/.. && SOPS_AGE_KEY_FILE=age.key sops kubernetes/apps/default/app-secrets.sops.yaml
