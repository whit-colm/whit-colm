---
title: "[Backend@Dotfile v3] Part 2 - Essential Services"
description: "Part 0 of docs reworking my Kubernetes Cluster"
summary: "Part 0 of docs reworking my Kubernetes Cluster"
date: 2022-07-16T12:13:01-05:00
draft: true
tags: ["bdv3", "kubernetes", "relevant"]
---

After bootstrapping, I my next steps were to make sure many of the services essential to my broader platform was installed.

# GitOps Management

With a new cluster, I decided to take the time to better handle how I actually managed the cluster. During v2 I kept a `~/k8s` directory which housed a pseudo-structured tree of helm value files and dangerously loose secrets. At my leisure I'd go around upgrading this, fixing that, and generally allowing many things to be neglected or at least very nonuniform.

I hope to fix that with GitOps. By managing my cluster through a single declarative point, I can eliminate (or at least severely minimize) the amount of administration I do by imprecisely bashing things around with a mallet.

I chose Flux over ArgoCD as while I do love a good web ui, Argo is a more collaborative platform and assumes a much deeper level of investment and configuration to get it going. While normally I adore that, a key point of this project is me not biting off more than I can chew.

## Prerequisite Key

Flux optionally can use a PGP key to sign commits, and as SOPS, the secrets manager I will install afterwards, requires a key to decrypt secrets, I generate it here (not shown as I'm not smart enough to do it via `--batch` so I had to meander through the interactive menu to generate it.

I created a new keyring specifically for talos and imported the new private key there. This allows me to move around the keyring if necessary (secured by other means of course) without endangering my personal keys. I'll refer to this file as `${KEYRING}`

## Installation

I decided to host the repository on [GitHub](https://github.com/dotfilesh/k8s). While I wanted the repo under an organization, I still needed a [personal access token](https://github.com/settings/tokens/new) with repo permissions.

> **Note**: For basic safety, I put a 1 year expiration period. This will have [to be rotated](https://github.com/fluxcd/flux2/discussions/2161) come 2023. Expect a surprise outage mid July then when I utterly forget about that fact.

Once I [installed the CLI tool](https://fluxcd.io/docs/installation/#install-the-flux-cli), I issued a [single big command](https://fluxcd.io/docs/cmd/flux_bootstrap_github/) and I was done:

```
export GITHUB_TOKEN=${TOKEN}
flux bootstrap github \
  --owner=dotfilesh \
  --repository=k8s \
  --path=./clusters/site0/ \
  --gpg-key-id=DDC65F2A2043C12C \
  --gpg-key-ring=${KEYRING}
```

This generated the repository and setup the necessary manifests to the cluster. I cloned the repo to my local machine, and was able to deploy new services to the cluster by adding a corresponding `yaml` file in the local `./clusters/site0` and pushing it to the main branch.

## Secrets Management

Directly related with using GitOps to manage the cluster is the necessity to not expose vital tokens like a moron. I've needed to do this for a while too, so there's that.

I decided to use Mozilla SOPS as from my understanding `secured-secrets` is rather lacking.

I will not go into excessive detail on how I did this, as with a few alterations I [just followed this](https://fluxcd.io/docs/guides/mozilla-sops/#configure-in-cluster-secrets-decryption).

- Ignore re-registering the git repository. That seems to be an oversight as the repository is registered to flux as a prerequisite for working at all. The resulting command was:

```bash
flux create kustomization kube-prometheus-stack \
  --interval=1h \
  --prune \
  --source=flux-monitoring \
  --path="./manifests/monitoring/kube-prometheus-stack" \
  --health-check-timeout=5m \
  --wait
```


# Setting Up Services

The nice thing about using Flux is the actual config files I end up using are available publicly as secrets are no longer an issue. I will provide a couple of  examples on what the config files generally look like, but otherwise will only note what services were installed and any challenges or quirks which I faced in doing so. I will also annotate the files in the GitHub repo for further reference.

## MetalLB

MetalLB provides a `LoadBalancer` object to the cluster, which otherwise is not readily available. This allows for port-forwarding without too big a headache. 

## cert-manager

cert-manager was tricky, as it not only required some fumbling around with cloudflare to get a token for letsencrypt, but it also **WILL NOT WORK** unless the helm chart is installed *before* any custom resources are created.

This can be fixed [through defining the former as a dependency of the latter](https://fluxcd.io/docs/components/kustomize/kustomization/#kustomization-dependencies).

I did this by separating the helm release and all custom objects into two separate directories, and setting a Flux Kustomization (`kustomize.toolkit.fluxcd.io/v1beta2` [not the other one](https://fluxcd.io/docs/faq/#are-there-two-kustomization-types)) for both.

```yaml
# ./clusters/site0/cert-manager/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  # helm is the directory where the helm-release.yaml is stored
  - helm
  - kustom-objects.yaml
  - kustom-helm.yaml
```

```
#./clusters/site0/cert-manager/kustom-helm.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  # by setting healthCheck to the helm release, this Kustomization is only
  # ready once the HelmRelease is.
  # Otherwise, Kustomization-s cannot rely on HelmRelease-s
  healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2beta1
    kind: HelmRelease
    name: cert-manager
    namespace: cert-manager
  interval: 1m
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
```

```
#./clusters/site0/cert-manager/kustom-objects.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: cert-manager-objects
  namespace: cert-manager
spec:
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
  interval: 1m
  # The location of all the other objects I want created.
  # in practice this is just another k8s Kustomization
  path: "./clusters/site0/cert-manager/objects"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
```

# EOF