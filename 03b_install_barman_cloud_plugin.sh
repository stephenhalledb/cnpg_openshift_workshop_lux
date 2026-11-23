#!/bin/bash
. ./config.sh

#Doc
echo "03b" > ./docs/docid

# Barman Cloud Plugin (CNPG-I plugin): backups and WAL archiving of the clusters
# go through it (ObjectStore resource + spec.plugins in the Cluster).
# Requirements: cert-manager, and the plugin must run in the namespace of the
# operator (openshift-operators with the OLM install of 02_install_cnpg_operator.sh).
# The release manifest is made for cnpg-system, so its namespace is replaced.

operator_namespace="openshift-operators"
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

print_command "oc get crd certificates.cert-manager.io; oc get deploy ${plugin_deployment} -n ${operator_namespace}\n"
check_cert_manager
cert_ok=$?
check_plugin
plugin_ok=$?

if [ ${cert_ok} -eq 0 ] && [ ${plugin_ok} -eq 0 ]; then
  exit 0
fi

if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
  print_warning "Install skipped (managed by the administrator): plugin_operator_minio_managed_by_admin=${plugin_operator_minio_managed_by_admin} in config.sh\n"
  exit 0
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
  print_command "curl -sL ${plugin_manifest_url} | sed 's/namespace: cnpg-system/namespace: ${operator_namespace}/' | oc apply -f -\n"
  curl -sSfL ${plugin_manifest_url} \
    | sed "s/namespace: cnpg-system/namespace: ${operator_namespace}/" \
    | ${kubectl_cmd} apply -f - || exit 1
  print_info "Waiting for the plugin to be ready...\n"
  wait_for check_plugin
  check_plugin || exit 1
fi
