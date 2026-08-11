# DPTP-4267: Prow control-plane cutover app.ci → core-ci

Big-bang cutover. **Do not apply by hand** — merge → Argo. Date TBD.

## Decisions (locked)

| Item | Choice |
|------|--------|
| Webhook | **DNS** (`hook.ci` / `prow.ci` → core-ci) **and** GitHub App webhook URL |
| QCI / quay-proxy | **Stay on app.ci** (core-ci QCI cache unused) |
| ImageStreams / release-controller | **Stay on app.ci**; RC must talk to core-ci for ProwJobs |
| Gangway tokens | **Pre-create** on core-ci; swap day-of (old tokens invalid) |
| Plugins | Ported from app.ci `03_deployment` |
| app.ci freeze | `replicas: 0` in app.ci deploy YAMLs (same PR) |

## What this branch ships

### core-ci (`clusters/core-ci/prow/`)

- Machinesets `worker-prow-services` (existing)
- Control plane: hook, ghproxy, PCM, crier, tide, horologium, sinker (**replicas 1** at cutover)
- Deck / gcsweb / private decks, statusreconciler, gangway, plugins, tot, pipeline-controller
- Ingress: `prow.ci.openshift.org` + `hook.ci.openshift.org`
- Apps Route on hook kept for pre-cutover smoke
- ProwJob CRD under `01_crd/`

### Wave 1 — DPTP frontends / bots (git-only, this branch)

Copied from `clusters/app.ci/` into `clusters/core-ci/` with `worker-prow-services` pin.
**Do not freeze app.ci wave-1 deploys in git** (merge would take prod down). **Do not `oc apply`.**

| Dir / asset | Notes |
|-------------|--------|
| `ci-operator-configresolver`, `pod-scaler`, `payload-testing-ui` | config.ci / steps.ci / resources.ci / pr-payload-tests.ci |
| `assets/docs.yaml`, `helpdesk-faq.yaml`, `slack-bot.yaml` | docs.ci, cluster-display, helpdesk-faq.ci, slack.ci |
| `backport-verifier` | bugs.ci → Service `backport-verifier` |
| `ci-chat-bot` | clusterbot.ci |
| `dex` | idp.ci — **one issuer**; DNS flip is the cutover |
| `vault` | vault.ci + selfservice.vault.ci — **replicas 0** (see below) |
| `dgraph`, `ephemeral-cluster`, `assets/dptp-controller-manager.yaml` | `--registry-cluster-name=app.ci` kept (IS stay on app.ci) |
| `jira-lifecycle-plugin`, `job-trigger-controller-manager`, `repo-*`, `result-aggregator`, `publicize/_config.yaml` | controllers / UIs |
| `ship-status-dash` | ship-status.ci (Ingress already in that dir) |
| `grafana-loki`, `ci-grafana` | grafana-loki.ci; `ci-grafana` operator pods **not** pinned |
| `sippy-redirector` | sippy.ci in ns `bparees` (same as app.ci) |
| `crt-admission-webhooks` | **master** DaemonSet — not pinned to prow-services |
| `prow-monitoring` | README only (same as app.ci) |

**Not copied**

- `ipi-deprovision` BuildConfig — needs app.ci `ocp` ImageStreams
- `assets/oauth.yaml` — cluster `OAuth` singleton; applying would clobber core-ci IdP config

**Vault (hard)**

core-ci vault STS uses the **same GCS bucket** (`vault-ci-openshift-clone`) as app.ci.
Replicas are **0**. Scale to 3 only after app.ci vault is stopped. Two HA vaults on one bucket **corrupt data**.

**Ingress (DNS not flipped)**

Split from the single app.ci `prow` Ingress:

- `ingress-prow.yaml` — prow.ci, hook.ci
- `ingress-prow-internal.yaml` — deck-internal.ci
- `ingress-dptp-frontends.yaml` — config/steps/bugs/slack/docs/cluster-display/selfservice.vault/resources/pr-payload-tests/helpdesk-faq
- plus vault, dex, ship-status, grafana-loki, cluster-bot, sippy Ingress objects in those dirs / `cert-manager/`

cert-manager HTTP-01 for those names **fails until DNS points at core-ci**.

### app.ci freeze (wave 0 Prow only)

Deployments set to **replicas 0**: hook, PCM, tide, horologium, sinker, crier, statusreconciler, gangway, deck (template).

Wave 1 app.ci deploys stay at current replicas until the frontend DNS cutover.

## Sync / day-of order

1. **Preflight (before merge)**  
   - Secret-bootstrap: all core-ci `ci` secrets (deck, tide, gangway, cookie, GCS, github app, build-farm kubeconfigs, …)  
   - Gangway tokens **pre-created** on core-ci; publish consumer swap list  
   - RC kubeconfig/SA can create ProwJobs on **core-ci** `ci`  
   - cert-manager `cert-issuer` works on core-ci  
   - Confirm Argo apps cover `clusters/core-ci/prow` + app.ci freeze paths  

2. **Merge PR** (Argo)  
   - Prefer sync **core-ci first**, verify deploys Ready  
   - Then sync **app.ci** freeze (replicas 0)  

3. **DNS + GitHub App**  
   - Point `hook.ci.openshift.org` / `prow.ci.openshift.org` at core-ci ingress  
   - Update GitHub App webhook to `https://hook.ci.openshift.org/hook`  
   - Verify HMAC delivery on core-ci hook  
   - Wave 1 names (`config.ci`, `slack.ci`, `idp.ci`, `vault.ci`, …) flip in a later step **after** those pods are Ready; vault only after app.ci vault is down  

4. **Validate**  
   - Presubmit PJ → farm pod completes  
   - Tide merge on a test PR  
   - Horologium periodics appear once (not doubled)  
   - Deck UI loads; GCS logs  
   - Gangway submit with **new** token  
   - RC creates verification PJ on core-ci  

5. **Revert** (if needed)  
   - DNS + GitHub App → app.ci  
   - Revert git (or restore app.ci replicas / set core-ci tide|horologium|sinker|hook|PCM to 0)  
   - Re-issue note: gangway may need app.ci tokens again  

## Sinker

Only **one** sinker may clean shared `pod_namespace: ci` on build farms.

| Phase | app.ci sinker | core-ci sinker |
|-------|---------------|----------------|
| Before cutover | 1 | 0 |
| After cutover | 0 | 1 |

## QCI / registry (unchanged)

- `quay-proxy.ci.openshift.org` auth = **app.ci** tokens  
- IS tagging / `sync-is-from-qci.sh` stays app.ci-scoped  
- Do **not** depend on core-ci pull-through caches for cutover  

## Release-controller ↔ core-ci

RC stays on app.ci with release ImageStreams.

Required before cutover (owners to confirm in-cluster):

1. RC can create/list/watch ProwJobs on **core-ci** (`prowjob_namespace: ci`)  
2. core-ci PCM keeps `app.ci` kubeconfig for jobs touching app.ci IS/registry  
3. Build farms unchanged  

## Gangway

Moving gangway invalidates existing tokens (new host / OAuth / SA issuer).

- Pre-create parallel token secrets under `clusters/core-ci/gangway-tokens/` (see README there)  
- Day-of: point consumers at core-ci gangway URL + new tokens  
- `clusters/app.ci/gangway-tokens/*` remain until consumers migrated  

## Secrets checklist (core-ci `ci`)

At minimum (extend secret-bootstrap `to: cluster: core-ci` as needed):

- [ ] `openshift-prow-github-app` (hmac, cert, appid)  
- [ ] `cookie`  
- [ ] `slack-credentials-prow`  
- [ ] GCS publisher SA secrets (crier/tide/deck)  
- [ ] `deck` / OAuth related  
- [ ] `gangway` / `gangway-session-secret` / TLS  
- [ ] Build-farm kubeconfigs: hook, PCM, crier, sinker, tide, deck  
- [ ] Plugin secrets (cherrypick, etc.) as on app.ci  
- [ ] Wave 1: dex (`dex-static-user`, `*-secret` OIDC clients), vault unseal/GCS, slack-bot, ci-chat-bot kubeconfigs, helpdesk-faq, oauth2-proxy for vault SCM  

## Local smoke (pre-cutover only)

```bash
~/CI/scripts/core-ci-prow/status.sh
~/CI/scripts/core-ci-prow/hmac-smoke.sh
# mkpj must-finish only after app.ci sinker is 0 (cutover) or isolation exists
```

## Explicit non-goals this PR

- Moving QCI / quay-proxy / release ImageStreams off app.ci  
- Incremental hook-reverse-proxy canary (#5345) — superseded by big-bang  
- Changing `ci-staging`  
- Freezing app.ci wave-1 frontends (configresolver, slack, dex, docs, …)  
- Dual-running vault against the shared GCS bucket  

## Still missing before any real cutover (wave 0 gaps)

- `prowjob-dispatcher`, boskos (+ cleaner/reaper), exporter on core-ci  
- Plugin freeze on app.ci  
- secret-bootstrap completeness  
- Machineset `worker-prow-services` min ≥ 2–3 (still min 0)  
- RC kubeconfig → core-ci; gangway token copies  
