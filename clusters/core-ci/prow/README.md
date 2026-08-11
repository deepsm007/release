# Prow on core-ci (DPTP-4267)

Production Prow **control plane** target for cutover from app.ci.

**Cutover runbook:** [CUTOVER.md](./CUTOVER.md)

## Layout

| Path | Purpose |
|------|---------|
| `01_crd/` | ProwJob CRD + RBAC |
| `03_deployment/` | Controllers, plugins, ingress (prow + wave-1 frontends) |
| `../machineset/worker-prow-services-amd64.yaml` | Node pool for these pods |
| `../gangway-tokens/` | Pre-create gangway tokens (cutover) |
| `../` wave-1 dirs | dex, vault (replicas 0), configresolver, slack, docs, … — see CUTOVER.md |

## Node placement

All control-plane pods use:

```yaml
nodeSelector:
  node-role.kubernetes.io/worker-prow-services: worker-prow-services
tolerations:
- key: node-role.kubernetes.io/worker-prow-services
  operator: Equal
  value: worker-prow-services
  effect: NoSchedule
```

## Local smoke (before DNS cutover)

```bash
~/CI/scripts/core-ci-prow/status.sh
~/CI/scripts/core-ci-prow/hmac-smoke.sh   # apps Route only
```

Hook apps Route (`hook-ci.apps.master…`) is for pre-cutover tests. Production is
`hook.ci.openshift.org` via `ingress-prow.yaml` after DNS + GitHub App cutover.

## Stays on app.ci

- QCI / quay-proxy auth and ImageStreams  
- release-controller + release IS (RC must create PJs on core-ci)  
- `ci-staging` sandbox  

## Do not

- Apply manifests manually to core-ci for cutover (Argo on merge)  
- Run two sinkers against shared `pod_namespace: ci`  
- Expect app.ci gangway tokens to work on core-ci  
