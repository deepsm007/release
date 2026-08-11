# Gangway tokens on core-ci (DPTP-4267)

Pre-create tokens here **before** cutover. Day-of, consumers switch URL + token;
tokens issued against **app.ci** gangway become invalid.

## Pattern

Mirror `clusters/app.ci/gangway-tokens/<team>/` onto:

`clusters/core-ci/gangway-tokens/<team>/`

Each team directory typically holds RBAC / secret bootstrap entries that mint
a token usable against gangway on **this** cluster.

## Day-of consumer checklist

For every entry under `clusters/app.ci/gangway-tokens/`:

1. Ensure matching core-ci token exists and is tested against core-ci gangway Route/Ingress  
2. Update automation with new token + core-ci gangway endpoint  
3. Confirm submit works once DNS/App cutover is done  

## Do not

- Assume app.ci tokens work against core-ci gangway  
- Delete app.ci token manifests until all consumers confirmed migrated  

See `clusters/core-ci/prow/CUTOVER.md`.
