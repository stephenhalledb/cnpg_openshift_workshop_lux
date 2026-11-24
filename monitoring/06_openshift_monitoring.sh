#!/bin/bash
# Turns Prometheus monitoring of the Postgres clusters on or off on an
# OpenShift (CRC) cluster, using the built-in OpenShift monitoring stack.
# It follows enable_prometheus_monitoring in config.sh:
#   yes : enables monitoring for user-defined projects (ConfigMap
#         cluster-monitoring-config, needs cluster-admin) and creates a
#         PodMonitor for all Postgres clusters in the demo namespace
#   no  : deletes the PodMonitor and disables monitoring for user-defined projects
# Do not use the Helm based scripts of this folder (01 to 05) on OpenShift:
# they install a second Prometheus that conflicts with the OpenShift one.

cd "$(dirname "$0")" || exit 1
. ../config.sh

#Doc
echo "monitoring" > ../docs/docid

monitoring_namespace="openshift-monitoring"
monitoring_configmap="cluster-monitoring-config"

# Set enableUserWorkload to true|false in the ConfigMap (keeps other settings)
set_user_workload() {
  local value="$1" current tmp
  current=$(${kubectl_cmd} get configmap ${monitoring_configmap} -n ${monitoring_namespace} \
    -o jsonpath='{.data.config\.yaml}' 2>/dev/null)

  tmp=$(mktemp)
  { printf '%s\n' "${current}" | grep -v -E '^enableUserWorkload:' | grep -v '^$'
    echo "enableUserWorkload: ${value}"; } > "${tmp}"

  print_command "oc apply configmap ${monitoring_configmap} (enableUserWorkload: ${value})\n"
  ${kubectl_cmd} create configmap ${monitoring_configmap} -n ${monitoring_namespace} \
    --from-file=config.yaml="${tmp}" --dry-run=client -o yaml | ${kubectl_cmd} apply -f - || { rm -f "${tmp}"; return 1; }
  rm -f "${tmp}"
}

user_workload_ready() {
  ${kubectl_cmd} get pod -n openshift-user-workload-monitoring \
    -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running
}

podmonitor_yaml() {
  cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: postgres-clusters
  namespace: ${namespace}
spec:
  selector:
    matchExpressions:
    - key: k8s.enterprisedb.io/cluster
      operator: Exists
  podMetricsEndpoints:
  - port: metrics
EOF
}

if [ "${enable_prometheus_monitoring}" == "yes" ]; then
  print_info "Prometheus monitoring: ON (enable_prometheus_monitoring=yes)\n"

  if ! ${kubectl_cmd} get prometheuses.monitoring.coreos.com -n ${monitoring_namespace} >/dev/null 2>&1; then
    print_error "OpenShift cluster monitoring is not running. On CRC set enable_prometheus_monitoring=\"yes\" in config.sh,\n"
    print_error "then run openshift_crc/start_openshift.sh (crc config set enable-cluster-monitoring true; crc stop; crc start).\n"
    exit 1
  fi

  set_user_workload true || { print_error "Could not enable monitoring for user-defined projects (cluster-admin needed)\n"; exit 1; }

  print_info "Waiting for prometheus-user-workload (up to 3 minutes)...\n"
  for i in $(seq 1 36); do
    user_workload_ready && break
    sleep 5
  done
  if user_workload_ready; then
    print_info "prometheus-user-workload: RUNNING\n"
  else
    print_warning "prometheus-user-workload is not running yet, check: oc get pods -n openshift-user-workload-monitoring\n"
  fi

  if ! ${kubectl_cmd} get namespace ${namespace} >/dev/null 2>&1; then
    print_warning "Namespace ${namespace} does not exist yet, run ./06_prepare_cluster.sh first. PodMonitor not created.\n"
    exit 1
  fi
  print_command "oc apply -n ${namespace} PodMonitor postgres-clusters (selects label k8s.enterprisedb.io/cluster)\n"
  podmonitor_yaml | ${kubectl_cmd} apply -f - || exit 1

  print_info "Prometheus monitoring is ON.\n"
  print_info "Check: OpenShift console > Observe > Targets, and Observe > Metrics (query: cnp_collector_up)\n"
else
  print_info "Prometheus monitoring: OFF (enable_prometheus_monitoring=${enable_prometheus_monitoring})\n"

  print_command "oc delete podmonitor postgres-clusters -n ${namespace}\n"
  ${kubectl_cmd} delete podmonitor postgres-clusters -n ${namespace} --ignore-not-found

  # Only touch the ConfigMap if it exists and monitoring for user projects is on
  if ${kubectl_cmd} get configmap ${monitoring_configmap} -n ${monitoring_namespace} \
      -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -q -E '^enableUserWorkload: *true'; then
    set_user_workload false || exit 1
  fi
  print_info "Prometheus monitoring is OFF.\n"
fi
