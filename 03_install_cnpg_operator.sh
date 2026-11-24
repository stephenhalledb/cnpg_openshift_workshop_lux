#!/bin/bash

. ./config.sh

operator_name="cloud-native-postgresql"
operator_namespace="openshift-operators"

# Print whether the operator is installed. Returns 0 if installed, 1 if not.
check_operator() {
  local csv phase
  csv=$(${kubectl_cmd} get subscription ${operator_name} -n ${operator_namespace} \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null)

  if [ -z "${csv}" ]; then
    print_error "Operator ${operator_name}: NOT INSTALLED\n"
    return 1
  fi

  phase=$(${kubectl_cmd} get csv ${csv} -n ${operator_namespace} \
    -o jsonpath='{.status.phase}' 2>/dev/null)

  if [ "${phase}" == "Succeeded" ]; then
    print_info "Operator ${operator_name}: INSTALLED (${csv}, phase: ${phase})\n"
    return 0
  else
    print_warning "Operator ${operator_name}: INSTALLING (${csv}, phase: ${phase:-unknown})\n"
    return 1
  fi
}

print_command "oc get subscription ${operator_name} -n ${operator_namespace}\n"
if check_operator; then
  exit 0
fi

if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
  print_warning "Install skipped (managed by the administrator): plugin_operator_minio_managed_by_admin=${plugin_operator_minio_managed_by_admin} in config.sh\n"
  exit 0
fi

# The operator image (docker.enterprisedb.com/k8s/...) is private: the operator
# pod needs the pull secret postgresql-operator-pull-secret in ${operator_namespace}
# (user k8s, password = EDB_SUBSCRIPTION_TOKEN from .credentials.sh).
# Without it the pod stays in ImagePullBackOff and the install never finishes.
# The secret is created by ./connect_edb_token.sh. An existing secret is kept as it
# is: to replace it (new token) run ./connect_edb_token.sh yourself.
ensure_pull_secret() {
  local secret="postgresql-operator-pull-secret"

  if ${kubectl_cmd} get secret ${secret} -n ${operator_namespace} >/dev/null 2>&1; then
    print_info "Pull secret ${secret} (${operator_namespace}): EXISTS\n"
    return 0
  fi

  print_command "./connect_edb_token.sh\n"
  if ./connect_edb_token.sh; then
    print_info "Pull secret ${secret} (${operator_namespace}): CREATED\n"
  else
    print_error "Pull secret ${secret} could not be created (is EDB_SUBSCRIPTION_TOKEN set in .credentials.sh?)\n"
    return 1
  fi
}

ensure_pull_secret || exit 1

print_command "oc get packagemanifests -n openshift-marketplace cloud-native-postgresql\n"
${kubectl_cmd} get packagemanifests -n openshift-marketplace cloud-native-postgresql
sleep 1

print_command "oc describe packagemanifests -n openshift-marketplace cloud-native-postgresql\n"
${kubectl_cmd} describe packagemanifests -n openshift-marketplace cloud-native-postgresql
sleep 1

# Cluster-wide installation
print_command "oc apply -f ./yaml/operator-subscription.yaml\n"
${kubectl_cmd} apply -f ./yaml/operator-subscription.yaml

# Wait up to 2 minutes for OLM to finish, then report the result
print_info "Waiting for the operator to be installed...\n"
for i in $(seq 1 24); do
  check_operator >/dev/null && break
  sleep 5
done
check_operator
