# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
# Force Flux to pull and apply latest git state
just kube reconcile

# Talos node management
just talos generate-config          # re-render talos configs from talconfig.yaml
just talos apply-node <ip>          # push config to a node
just talos upgrade-node <ip>        # upgrade Talos on a node
just talos upgrade-k8s              # upgrade Kubernetes version

# Re-render all templated files from cluster.toml
just configure

# Check Flux resource health
flux get ks -A
flux get hr -A
```

The kubeconfig lives at `./kubeconfig` in the repo root. Pass it explicitly: `kubectl --kubeconfig=kubeconfig ...`

## Architecture

**Stack:** Talos Linux (bare metal) → Kubernetes → FluxCD (GitOps) → Helm charts

**Configuration pipeline:** `cluster.toml` is the single source of truth. Running `just configure` feeds it through [makejinja](https://github.com/mirkolenz/makejinja) to render `kubernetes/` and `talos/` configs. Talos node config is managed by [talhelper](https://budimanjojo.github.io/talhelper/latest/) reading `talos/talconfig.yaml`.

**Flux entrypoint:** `kubernetes/flux/cluster/ks.yaml` defines the root `cluster-apps` Kustomization pointing at `./kubernetes/apps`. That kustomization patches all child `Kustomization` and `HelmRelease` resources with cluster-wide defaults (SOPS decryption, CRD handling, retry strategies).

**App structure — every app follows this layout:**

```
kubernetes/apps/<namespace>/
  kustomization.yaml          ← lists all ks.yaml files in this namespace
  <app-name>/
    ks.yaml                   ← Flux Kustomization (sourceRef: flux-system GitRepository)
    app/
      kustomization.yaml      ← lists helmrelease + source
      helmrelease.yaml        ← HelmRelease referencing the chart source
      ocirepository.yaml      ← OR helmrepository.yaml (for non-OCI charts)
```

Chart sources are usually `OCIRepository` (e.g. `oci://ghcr.io/stakater/charts/reloader`). Use `HelmRepository` only when the chart isn't published as OCI.

**Secrets:** SOPS + age. The age key is at `./age.key`. Encrypted secrets follow the pattern `*.sops.yaml`. The `kubernetes/components/sops/` component is referenced from namespace-level kustomizations and injects a `cluster-secrets` Secret; app ks.yaml files reference it via `postBuild.substituteFrom` for variable substitution.

**Networking:**
- Cilium as CNI with BGP peering to the router (`10.20.0.1`) for LoadBalancer IP advertisement
- LoadBalancer VIPs: API `10.20.0.2`, internal gateway `10.20.0.3`, DNS `10.20.0.4`, external `10.20.0.5`
- Envoy Gateway handles HTTP routing (`envoy-internal` for LAN-only, `envoy-external` for public via cloudflared tunnel)
- k8s-gateway serves in-cluster DNS for `winstead.io` — home DNS must forward that domain to `10.20.0.4`
- Cloudflare tunnel + external-dns handle public ingress and DNS records automatically

**Adding a new app:** create the four files above, add `./smb-csi-driver/ks.yaml` to the namespace's `kustomization.yaml`, commit, push, then run `just kube reconcile` and verify with `flux get ks -A` and `flux get hr -A`.
