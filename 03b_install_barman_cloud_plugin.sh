#!/bin/bash
. ./config.sh

#Doc
echo "03b" > ./docs/docid

# Barman Cloud Plugin (CNPG-I plugin): backups and WAL archiving of the clusters
# go through it (ObjectStore resource + spec.plugins in the Cluster).
# Requirements: cert-manager, and the plugin must run in the namespace of the
# operator (openshift-operators with the OLM install of 02_install_cnpg_operator.sh).
# The release manifest is made for cnpg-system, so its namespace is replaced.
# It also pins runAsUser/runAsGroup 10001, which the OpenShift restricted-v2 SCC
# rejects (the UID must be in the range of the namespace): those two lines are removed.
# Its rights are only for postgresql.cnpg.io: yaml/barman-plugin-edb-rbac.yaml adds them
# for the EDB API group postgresql.k8s.enterprisedb.io.

export operator_namespace="openshift-operators"   # exported: used by envsubst
plugin_deployment="barman-cloud"
plugin_manifest_url="https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/${barman_cloud_plugin_version}/manifest.yaml"
cert_manager_manifest_url="https://github.com/cert-manager/cert-manager/releases/download/${cert_manager_version}/cert-manager.yaml"

# Print whether cert-manager is installed and ready. Returns 0 if ready, 1 if not.
check_cert_manager() {
  if ! ${kubectl_cmd} get crd certificates.cert-manager.io >/dev/null 2>&1; then
    print_error "cert-manager: NOT INSTALLED\n"
    return 1
  fi
  if ${kubectl_cmd} get deploy cert-manager-webhook -n cert-manager \
       -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q '^[1-9]'; then
    print_info "cert-manager: INSTALLED (webhook available)\n"
    return 0
  fi
  # cert-manager can also be installed by the Red Hat operator in another namespace
  if ${kubectl_cmd} get deploy -A -l app.kubernetes.io/name=webhook,app.kubernetes.io/instance=cert-manager \
       -o jsonpath='{.items[*].status.availableReplicas}' 2>/dev/null | grep -q '[1-9]'; then
    print_info "cert-manager: INSTALLED (webhook available)\n"
    return 0
  fi
  print_warning "cert-manager: INSTALLING (webhook not available yet)\n"
  return 1
}

# Print whether the plugin is installed and ready. Returns 0 if ready, 1 if not.
check_plugin() {
  local ready
  ready=$(${kubectl_cmd} get deploy ${plugin_deployment} -n ${operator_namespace} \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  if [ -z "${ready}" ] || [ "${ready}" == "0" ]; then
    if ${kubectl_cmd} get deploy ${plugin_deployment} -n ${operator_namespace} >/dev/null 2>&1; then
      print_warning "Barman Cloud Plugin: INSTALLING (not available yet)\n"
    else
      print_error "Barman Cloud Plugin: NOT INSTALLED\n"
    fi
    return 1
  fi
  print_info "Barman Cloud Plugin: INSTALLED (deployment ${plugin_deployment} in ${operator_namespace})\n"
  return 0
}

# The plugin only has rights on the postgresql.cnpg.io API group, the EDB operator
# uses postgresql.k8s.enterprisedb.io: grant the same rights (see the yaml file).
# Returns 0 if the rights exist (or were created), 1 if not.
rbac_yaml="./yaml/barman-plugin-edb-rbac.yaml"
check_edb_rbac() {
  if ${kubectl_cmd} get clusterrole plugin-barman-cloud-edb >/dev/null 2>&1 \
     && ${kubectl_cmd} get clusterrolebinding plugin-barman-cloud-edb >/dev/null 2>&1; then
    print_info "Plugin rights on postgresql.k8s.enterprisedb.io: EXIST\n"
    return 0
  fi
  print_error "Plugin rights on postgresql.k8s.enterprisedb.io: MISSING (the cluster cannot use the plugin)\n"
  return 1
}
apply_edb_rbac() {
  check_edb_rbac >/dev/null && return 0
  print_command "envsubst < ${rbac_yaml} | oc apply -f -\n"
  envsubst < ${rbac_yaml} | ${kubectl_cmd} apply -f - || return 1
  check_edb_rbac
}

print_command "oc get crd certificates.cert-manager.io; oc get deploy ${plugin_deployment} -n ${operator_namespace}\n"
check_cert_manager
cert_ok=$?
check_plugin
plugin_ok=$?

if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
  check_edb_rbac
  if [ ${cert_ok} -ne 0 ] || [ ${plugin_ok} -ne 0 ]; then
    print_warning "Install skipped (managed by the administrator): plugin_operator_minio_managed_by_admin=${plugin_operator_minio_managed_by_admin} in config.sh\n"
  fi
  exit 0
fi

if [ ${cert_ok} -eq 0 ] && [ ${plugin_ok} -eq 0 ]; then
  apply_edb_rbac
  exit $?
fi

# Wait up to 3 minutes until the given check function succeeds
wait_for() {
  local check=$1
  for i in $(seq 1 36); do
    ${check} >/dev/null && return 0
    sleep 5
  done
  return 1
}

if [ ${cert_ok} -ne 0 ]; then
  print_command "oc apply -f ${cert_manager_manifest_url}\n"
  ${kubectl_cmd} apply -f ${cert_manager_manifest_url} || exit 1
  print_info "Waiting for cert-manager to be ready...\n"
  wait_for check_cert_manager
  check_cert_manager || { print_error "cert-manager is not ready, the plugin is not installed\n"; exit 1; }
fi

if [ ${plugin_ok} -ne 0 ]; then
  print_command "curl -sL ${plugin_manifest_url} | sed (namespace, runAsUser/runAsGroup) | oc apply -f -\n"
  curl -sSfL ${plugin_manifest_url} \
    | sed -e "s/namespace: cnpg-system/namespace: ${operator_namespace}/" \
          -e '/runAsUser: 10001/d' -e '/runAsGroup: 10001/d' \
    | ${kubectl_cmd} apply -f - || exit 1
  print_info "Waiting for the plugin to be ready...\n"
  wait_for check_plugin
  check_plugin || exit 1
fi

apply_edb_rbac || exit 1
