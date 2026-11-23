#!/bin/bash
. ./config.sh

#Doc
echo "32" > ./docs/docid

# Hibernate: the cluster is hibernated when the operator sets the condition
# k8s.enterprisedb.io/hibernation=True (reason Hibernated) and all its pods are
# gone (the PVCs are kept). The script waits for it and prints a message while
# it waits. Timeout in seconds: HIBERNATION_WAIT_TIMEOUT (default 300).
hibernation_wait_timeout=${HIBERNATION_WAIT_TIMEOUT:-300}
hibernation_wait_interval=5
cluster_resource="cluster.postgresql.k8s.enterprisedb.io"

# Status of the hibernation condition of the cluster (True, False or empty)
hibernation_condition() {
  ${kubectl_cmd} get ${cluster_resource} ${cluster_name} -n ${namespace} \
    -o jsonpath='{.status.conditions[?(@.type=="k8s.enterprisedb.io/hibernation")].status}' 2>/dev/null
}

# Number of pods of the cluster that still exist
cluster_pods_left() {
  ${kubectl_cmd} get pods -n ${namespace} -l k8s.enterprisedb.io/cluster=${cluster_name} --no-headers 2>/dev/null \
    | wc -l | xargs
}

wait_for_hibernated() {
  local elapsed=0 pods
  while true; do
    pods=$(cluster_pods_left)
    if [ "$(hibernation_condition)" = "True" ] && [ "${pods}" = "0" ]; then
      print_info "Cluster ${cluster_name} is HIBERNATED.\n"
      return 0
    fi
    if [ ${elapsed} -ge ${hibernation_wait_timeout} ]; then
      print_error "Cluster ${cluster_name} is not hibernated after ${hibernation_wait_timeout} seconds (${pods} pods left).\n"
      print_error "Check: ${kubectl_cmd} get pods -n ${namespace}  and  ${kubectl_cnp} status ${cluster_name}\n"
      return 1
    fi
    print_warning "Waiting for cluster ${cluster_name} to reach HIBERNATED... (${pods} pods still running, ${elapsed}s)\n"
    sleep ${hibernation_wait_interval}
    elapsed=$((elapsed + hibernation_wait_interval))
  done
}

# Without a parameter, ask in the terminal: a) hibernate or b) resume
#   ./23_hibernation.sh        : asks
#   ./23_hibernation.sh on|off : does not ask (on = hibernate, off = resume)
i=$1
while [ -z "$i" ]; do
  printf "Cluster ${cluster_name}:\n"
  printf "  a) hibernate cluster\n"
  printf "  b) resume cluster\n"
  printf "Choose a or b [q to quit]: "
  read -r answer || exit 1
  case "${answer}" in
    a|A|on|ON)    i="on" ;;
    b|B|off|OFF)  i="off" ;;
    q|Q)          echo "Nothing changed"; exit 0 ;;
    *)            print_warning "Please answer a, b or q\n" ;;
  esac
done

case $i in
  "on")
    print_command "${kubectl_cnp} hibernate on ${cluster_name} -n ${namespace}\n"
    ${kubectl_cnp} hibernate on ${cluster_name} -n ${namespace} || exit 1
    wait_for_hibernated || exit 1
    ;;
  "off")
    print_command "${kubectl_cnp} hibernate off ${cluster_name} -n ${namespace}\n"
    ${kubectl_cnp} hibernate off ${cluster_name} -n ${namespace}
    ;;
  *)
    echo "usage: $0 [on|off]"
    exit 1
esac

