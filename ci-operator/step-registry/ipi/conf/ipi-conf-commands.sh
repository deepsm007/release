#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

cluster_name=${NAMESPACE}-${UNIQUE_HASH}

out=${SHARED_DIR}/install-config.yaml

if [[ -z "$RELEASE_IMAGE_LATEST" ]]; then
  echo "RELEASE_IMAGE_LATEST is an empty string, exiting"
  exit 1
fi

echo "Installing from release ${RELEASE_IMAGE_LATEST}"

ssh_pub_key=$(<"${CLUSTER_PROFILE_DIR}/ssh-publickey")
pull_secret=$(<"${CLUSTER_PROFILE_DIR}/pull-secret")

cat > "${out}" << EOF
apiVersion: v1
metadata:
  name: ${cluster_name}
pullSecret: >
  ${pull_secret}
sshKey: |
  ${ssh_pub_key}
EOF

excluding older releases because of the bug fixed in 4.10, see: https://bugzilla.redhat.com/show_bug.cgi?id=1960378
if (( ocp_minor_version > 10 || ocp_major_version > 4 )); then
  PATCH="${SHARED_DIR}/install-config-image-mirrors.yaml.patch"
  cat > "${PATCH}" << EOF
imageDigestSources:
- mirrors:
  - quay.io/openshift/ci
  source: quay-proxy.ci.openshift.org/openshift/ci
imageTagMirrors:
- mirrors:
  - quay.io/openshift/ci
  source: quay-proxy.ci.openshift.org/openshift/ci
EOF

  yq-go m -x -i "${out}" "${PATCH}"

  pull_secret=$(<"${CLUSTER_PROFILE_DIR}/pull-secret")
  mirror_auth=$(echo ${pull_secret} | jq '.auths["quay.io"].auth' -r)
  pull_secret_qci=$(jq --arg auth ${mirror_auth} --arg repo "quay-proxy.ci.openshift.org" '.["auths"] += {($repo): {$auth}}' <<<  $pull_secret)

  PATCH="/tmp/install-config-pull-secret.yaml.patch"
  cat > "${PATCH}" << EOF
pullSecret: >
  $(echo "${pull_secret_qci}" | jq -c .)
EOF
  yq-go m -x -i "${out}" "${PATCH}"
  rm "${PATCH}"
fi

if [ ${FIPS_ENABLED} = "true" ]; then
	echo "Adding 'fips: true' to install-config.yaml"
	cat >> "${out}" << EOF
fips: true
EOF
fi

if [ -n "${BASELINE_CAPABILITY_SET}" ]; then
	echo "Adding 'capabilities: ...' to install-config.yaml"
	cat >> "${out}" << EOF
capabilities:
  baselineCapabilitySet: ${BASELINE_CAPABILITY_SET}
EOF
        if [ -n "${ADDITIONAL_ENABLED_CAPABILITIES}" ]; then
            cat >> "${out}" << EOF
  additionalEnabledCapabilities:
EOF
            for item in ${ADDITIONAL_ENABLED_CAPABILITIES}; do
                cat >> "${out}" << EOF
    - ${item}
EOF
            done
        fi
fi

if [ -n "${PUBLISH}" ]; then
        echo "Adding 'publish: ...' to install-config.yaml"
        cat >> "${out}" << EOF
publish: ${PUBLISH}
EOF
fi

if [ -n "${FEATURE_SET}" ]; then
        echo "Adding 'featureSet: ...' to install-config.yaml"
        cat >> "${out}" << EOF
featureSet: ${FEATURE_SET}
EOF
fi

# FeatureGates must be a valid yaml list.
# E.g. ['Feature1=true', 'Feature2=false']
# Only supported in 4.14+.
if [ -n "${FEATURE_GATES}" ]; then
        echo "Adding 'featureGates: ...' to install-config.yaml"
        cat >> "${out}" << EOF
featureGates: ${FEATURE_GATES}
EOF
fi
