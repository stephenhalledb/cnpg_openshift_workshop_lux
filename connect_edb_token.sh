#!/bin/bash
# Connects the cluster (and this machine) to the private EDB image repository
# docker.enterprisedb.com with the EDB_SUBSCRIPTION_TOKEN of .credentials.sh:
#   1. OpenShift: creates (or replaces) the pull secret
#      postgresql-operator-pull-secret in openshift-operators. The operator pod
#      needs it to pull its image, without it the pod stays in ImagePullBackOff.
#   2. docker login on this machine (only if docker is installed). A failed login
#      is only a warning, it does not change the result of the script.
# Called by 03_install_cnpg_operator.sh when the secret is missing. Run it by hand
# after a change of the token: an existing secret is replaced.
# Exit code: 0 = pull secret created, 1 = token not set or secret not created.

[ -f ./.credentials.sh ] && . ./.credentials.sh

if [ -z "${EDB_SUBSCRIPTION_TOKEN}" ]; then
  echo "EDB_SUBSCRIPTION_TOKEN is not set: add it to .credentials.sh (see README, EDB Repo)" >&2
  exit 1
fi

# OpenShift
oc delete secret -n openshift-operators postgresql-operator-pull-secret --ignore-not-found
oc create secret docker-registry postgresql-operator-pull-secret \
  -n openshift-operators \
  --docker-server=docker.enterprisedb.com \
  --docker-username=k8s \
  --docker-password="${EDB_SUBSCRIPTION_TOKEN}" || exit 1

# Local machine (the password is read from stdin, not shown in the process list)
if command -v docker >/dev/null 2>&1; then
  echo "${EDB_SUBSCRIPTION_TOKEN}" | docker login docker.enterprisedb.com \
    --username k8s \
    --password-stdin \
    || echo "Warning: docker login failed (the pull secret in OpenShift was created)" >&2
else
  echo "docker not installed: docker login skipped"
fi
