# Prow on core-ci

Bootstrap of the Prow control plane on core-ci. First step of moving services off app.ci. GitHub production traffic still hits app.ci.

## What this is not

- No production webhook cutover (`hook.ci.openshift.org` DNS untouched)
- No redirect proxy in front of app.ci
- Not taking over merges or periodics from app.ci

## What’s running

| Component | Replicas | Why |
|-----------|----------|-----|
| ghproxy | 1 | Local GitHub API cache; ClusterIP only |
| hook | 1 | ClusterIP + default apps Route for manual tests only |
| prow-controller-manager | 1 | Schedules ProwJobs onto build farms |
| crier | 1 | Reporting path present; use `report: false` for smoke PJs |
| sinker | 0 | **Must stay 0** while app.ci owns build-farm cleanup (see below) |
| tide | 0 | Stay off until we intentionally split repos |
| horologium | 0 | Stay off so we don’t double-create periodics |

### Sinker / dual hub

core-ci and app.ci share build-farm kubeconfigs. If both run sinker, each treats the other’s pods as orphaned and deletes them. Keep core-ci sinker at `0` until build-farm ownership is partitioned (or sinker gains an exclude mechanism). app.ci sinker still cleans app.ci pods — and will also orphan-delete pods for ProwJobs that exist **only** on core-ci.

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

## Local testing

### 1. Hook HMAC (default apps Route only)

Route host is the cluster apps domain — **not** `hook.ci.openshift.org`:

`https://hook-ci.apps.master.ci.devcluster.openshift.com/hook`

```bash
# NEED: prove hook HMAC accept/reject on core-ci
set -euo pipefail
URL='https://hook-ci.apps.master.ci.devcluster.openshift.com/hook'
BODY='{"zen":"core-ci-hmac-smoke","hook_id":1,"repository":{"full_name":"openshift/ci-tools","name":"ci-tools","owner":{"login":"openshift"}},"sender":{"login":"smoke-test"}}'

HMAC=$(oc --context core-ci --as system:admin get secret openshift-prow-github-app -n ci -o jsonpath='{.data.hmac}' | base64 -d)
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$HMAC" | awk '{print $2}')
unset HMAC

# bad -> 403
curl -sk -w '\nHTTP %{http_code}\n' -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: ping' \
  -H 'X-Hub-Signature-256: sha256=deadbeef' \
  -d "$BODY"

# good -> 200 Event received
curl -sk -w '\nHTTP %{http_code}\n' -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: ping' \
  -H "X-Hub-Signature-256: sha256=${SIG}" \
  -d "$BODY"
```

### 2. Manual ProwJob (PCM → build farm)

Create a ProwJob on core-ci with `mkpj`. Set `report: false` so core-ci crier does not comment on GitHub.

**Caveat:** app.ci sinker may still delete the build-farm pod as orphaned (no matching PJ on app.ci). Scheduling path is proven if PCM creates the pod; long-running completion is unreliable until sinker ownership is fixed.

```bash
cd /path/to/openshift/release

mkpj \
  --job=pull-ci-openshift-ci-tools-main-unit \
  --config-path=core-services/prow/02_config/_config.yaml \
  --job-config-path=ci-operator/jobs/openshift/ci-tools \
  --pull-number=<PR> \
  > /tmp/core-ci-smoke-pj.yaml

# set report: false, unique metadata.name, namespace: ci — then:
oc --context core-ci --as system:admin apply -f /tmp/core-ci-smoke-pj.yaml

oc --context core-ci --as system:admin get prowjob -n ci <name>
# pod lands on spec.cluster, e.g. build06
```

## Next

Canary: repo partitioning, tide/horologium ownership, webhook proxy — not `hook.ci` DNS yet. Do not scale core-ci sinker until dual-hub cleanup is safe.
