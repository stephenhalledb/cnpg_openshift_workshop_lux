#!/bin/bash
# Scales the number of instances of the cluster (cluster_name in config.sh).
#   ./15_scale.sh            : shows the current number of instances and asks for
#                              the new number
#   ./15_scale.sh n          : scale to n instances
#   ./15_scale.sh out [n]    : scale out to n instances (default: current + 1)
#   ./15_scale.sh in [n]     : scale in to n instances (default: current - 1)
. ./config.sh

#Doc
echo "14" > ./docs/docid

cluster_resource="cluster.postgresql.k8s.enterprisedb.io"

current_instances() {
  ${kubectl_cmd} get ${cluster_resource} ${cluster_name} -n ${namespace} -o jsonpath='{.spec.instances}' 2>/dev/null
}

# is_valid_target <direction> <target> <current>: returns 0 if the target is a
# whole number >= 1 that differs from the current one (and goes the right way if
# a direction is given), else prints why and returns 1
is_valid_target() {
  local direction="$1" target="$2" current="$3"
  case "${target}" in
    ''|*[!0-9]*) print_warning "'${target}' is not a number.\n"; return 1 ;;
  esac
  if [ "${target}" -lt 1 ]; then
    print_warning "The number of instances must be at least 1.\n"; return 1
  fi
  if [ "${target}" -eq "${current}" ]; then
    print_warning "The cluster already has ${current} instances.\n"; return 1
  fi
  if [ "${direction}" = "out" ] && [ "${target}" -le "${current}" ]; then
    print_warning "To scale out, choose more than the current ${current} instances.\n"; return 1
  fi
  if [ "${direction}" = "in" ] && [ "${target}" -ge "${current}" ]; then
    print_warning "To scale in, choose fewer than the current ${current} instances.\n"; return 1
  fi
}

# Asks the new number of instances. Sets $target. Returns 1 to quit.
ask_target() {
  local answer
  while true; do
    printf "Number of instances (currently %s) [q to quit]: " "${current}"
    read -r answer || return 1
    case "${answer}" in q|Q) return 1 ;; esac
    target="${answer}"
    is_valid_target "" "${target}" "${current}" && return 0
  done
}

current=$(current_instances)
if [ -z "${current}" ]; then
  print_error "Cluster ${cluster_name} not found in namespace ${namespace} (oc whoami? ./05_install_cluster.sh?).\n"
  exit 1
fi

case "$1" in
  out) direction="out"; target="${2:-$((current + 1))}" ;;
  in)  direction="in";  target="${2:-$((current - 1))}" ;;
  "")  direction="" ;;
  *)   direction=""; target="$1" ;;
esac

if [ -z "$1" ]; then
  ask_target || { echo "Nothing changed."; exit 0; }
else
  is_valid_target "${direction}" "${target}" "${current}" || exit 1
fi

print_command "${kubectl_cmd} scale ${cluster_resource} ${cluster_name} -n ${namespace} --replicas=${target}\n"
${kubectl_cmd} scale ${cluster_resource} ${cluster_name} -n ${namespace} --replicas=${target}
