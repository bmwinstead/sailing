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
    SOPS_AGE_KEY_FILE={{ justfile_directory() }}/../age.key sops {{ justfile_directory() }}/apps/default/app-secrets.sops.yaml
