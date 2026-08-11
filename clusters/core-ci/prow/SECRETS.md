# Secret-bootstrap gaps for core-ci Prow cutover (DPTP-4267)

Ensure `core-services/ci-secret-bootstrap/_config.yaml` has `to: cluster: core-ci`
(and namespace `ci` where appropriate) for everything app.ci Prow needs.

Already partially done earlier (crier/PCM/sinker/cookie/slack/GCS bits) — verify
and extend before merge.

## Must verify on core-ci `ci`

| Secret / item | Used by |
|---------------|---------|
| `openshift-prow-github-app` | hook, tide, plugins, gangway, … |
| `cookie` | deck |
| `slack-credentials-prow` | crier/hook plugins |
| GCS SA secrets for crier/tide/deck | reporting / spyglass |
| `sa.*.buildXX.config` for hook, PCM, crier, sinker, tide, deck | farm access |
| `sa.*.app.ci.config` for PCM/hook as needed | IS/registry on app.ci |
| gangway TLS / session secret | gangway |
| plugin-specific secrets | cherrypick, etc. |
| OAuth / dex bits for deck if required | deck UI login |
| dex OIDC client secrets + `dex-static-user` | `idp.ci` (wave 1) |
| vault unseal / GCS / TLS | `vault` ns (wave 1; keep replicas 0 until app.ci vault is down) |
| slack-bot / ci-chat-bot / helpdesk-faq | wave 1 frontends |

After editing bootstrap config, run generator/bootstrap per DPTP process (not
documented here). Confirm secrets exist **before** cutover merge.

See [CUTOVER.md](./CUTOVER.md).
