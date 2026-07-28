# Prow on core-ci

Bootstrap of the Prow control plane on core-ci. This is the first step of moving services off app.ci. Nothing here is wired to GitHub yet.

## What this is not

- No webhook endpoint for GitHub (no Route/Ingress on hook)
- No DNS changes and no redirect proxy in front of app.ci
- Not taking over merges or periodics from app.ci

## What’s running

| Component | Replicas | Why |
|-----------|----------|-----|
| ghproxy | 1 | Local GitHub API cache; ClusterIP only |
| hook | 1 | Deployed for smoke, but not exposed publicly |
| prow-controller-manager | 1 | Secrets landed; still no webhook traffic |
| crier | 1 | Same |
| sinker | 1 | Same |
| tide | 0 | Stay off until we intentionally split repos |
| horologium | 0 | Stay off so we don’t double-create periodics |

Pods land on the `worker-prow-services` MachineSets:

```yaml
nodeSelector:
  node-role.kubernetes.io/worker-prow-services: worker-prow-services
tolerations:
- key: node-role.kubernetes.io/worker-prow-services
  operator: Equal
  value: worker-prow-services
  effect: NoSchedule
```

When we’re ready for canary traffic, the next work is secrets, then carefully scaling the zeroed controllers and routing a small set of repos — not flipping `hook.ci` DNS yet.
