#!/bin/bash
# Checks the data of the restored cluster (cluster_restore).
# The restore (12_restore_cluster.sh) takes a few minutes: the cluster has to
# fetch the backup and the WAL files from the object storage first. This script
# waits until the restore cluster is up and running, and prints a message while
# it waits. It stops with an error if the cluster does not exist (run
# 12_restore_cluster.sh first) or is not ready after the timeout.
# Timeout in seconds: RESTORE_WAIT_TIMEOUT (default 600).

source ./config.sh

restore_wait_timeout=${RESTORE_WAIT_TIMEOUT:-600}
restore_wait_interval=5
restore_cluster_resource="cluster.postgresql.k8s.enterprisedb.io"

# Reads one field of the restore cluster (jsonpath in $1), empty if not available
restore_cluster_field() {
  ${kubectl_cmd} get ${restore_cluster_resource} ${cluster_restore} -n ${namespace} -o jsonpath="$1" 2>/dev/null
}

# The restore cluster is up when its Ready condition is True
restore_cluster_ready() {
  [ "$(restore_cluster_field '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]
}

wait_for_restore_cluster() {
  local elapsed=0 phase ready instances

  if ! ${kubectl_cmd} get ${restore_cluster_resource} ${cluster_restore} -n ${namespace} >/dev/null 2>&1; then
    print_error "Restore cluster ${cluster_restore} not found in namespace ${namespace}.\n"
    print_error "Run ./12_restore_cluster.sh first (or check that you are logged in: oc whoami).\n"
    return 1
  fi

  while ! restore_cluster_ready; do
    if [ ${elapsed} -ge ${restore_wait_timeout} ]; then
      print_error "Restore cluster ${cluster_restore} is not ready after ${restore_wait_timeout} seconds.\n"
      print_error "Check: ${kubectl_cnp} status ${cluster_restore}  and  ${kubectl_cmd} get pods -n ${namespace}\n"
      return 1
    fi
    phase=$(restore_cluster_field '{.status.phase}')
    ready=$(restore_cluster_field '{.status.readyInstances}')
    instances=$(restore_cluster_field '{.spec.instances}')
    print_warning "Restore cluster ${cluster_restore} is being built, waiting... (${phase:-starting}, ready instances: ${ready:-0}/${instances:-?}, ${elapsed}s)\n"
    sleep ${restore_wait_interval}
    elapsed=$((elapsed + restore_wait_interval))
  done
  print_info "Restore cluster ${cluster_restore} is up and running.\n"
}

wait_for_restore_cluster || exit 1

print_command "echo \"select version();\" | ${kubectl_cnp} psql ${cluster_restore}\n"
print_command "echo \"select * from test;\" | ${kubectl_cnp} psql ${cluster_restore}\n"

#cat sql/verify_data.sql | ${kubectl_cnp} psql ${cluster_restore} # will throw "Unable to use a TTY" and we want omit a "2>/dev/null"
${kubectl_cnp} psql -n ${namespace} ${cluster_restore} -- -c "$(cat sql/verify_data.sql)"
