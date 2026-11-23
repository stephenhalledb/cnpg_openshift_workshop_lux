#!/bin/bash
# Like 06_show_status.sh, but it asks which Postgres cluster to display.
# It lists the clusters of the default namespace (the current oc project; the
# namespace from config.sh if no project is selected) and shows the status of
# the chosen one, refreshed every second (quit with Ctrl+C).
#   ./show_status.sh              : lists the clusters and asks which one
#   ./show_status.sh <cluster>    : shows that cluster without asking
# With only one cluster in the namespace it is chosen without asking.

. ./config.sh

cluster_resource="cluster.postgresql.k8s.enterprisedb.io"

# Default namespace = current project of oc, else the demo namespace of config.sh
show_namespace=$(${kubectl_cmd} config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null)
show_namespace=${show_namespace:-${namespace}}

# Names of the clusters in the namespace, one per line
list_clusters() {
  ${kubectl_cmd} get ${cluster_resource} -n "${show_namespace}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
}

# Asks which cluster ($@ = the names), prints the chosen name. The question goes
# to stderr so that the answer can be captured.
choose_cluster() {
  local names=("$@") answer i
  while true; do
    printf "Clusters in namespace %s:\n" "${show_namespace}" >&2
    for i in "${!names[@]}"; do
      printf "  %d) %s\n" $((i + 1)) "${names[$i]}" >&2
    done
    printf "Which cluster do you want to display? [1-%d, q to quit]: " "${#names[@]}" >&2
    read -r answer || return 1
    case "${answer}" in
      q|Q) return 1 ;;
      ''|*[!0-9]*) ;;                                   # not a number: ask again
      *) if [ "${answer}" -ge 1 ] && [ "${answer}" -le "${#names[@]}" ]; then
           printf '%s\n' "${names[$((answer - 1))]}"
           return 0
         fi ;;
    esac
    print_warning "Invalid choice: '${answer}'\n" >&2
  done
}

if [ -n "$1" ]; then
  selected="$1"
else
  clusters=()
  while IFS= read -r name; do
    [ -n "${name}" ] && clusters+=("${name}")
  done < <(list_clusters)

  if [ ${#clusters[@]} -eq 0 ]; then
    print_error "No cluster found in namespace ${show_namespace} (change it with: oc project <namespace>).\n"
    exit 1
  elif [ ${#clusters[@]} -eq 1 ]; then
    selected="${clusters[0]}"
    print_info "Only one cluster in namespace ${show_namespace}: ${selected}\n"
  else
    selected=$(choose_cluster "${clusters[@]}") || { echo "No cluster selected."; exit 1; }
  fi
fi

print_command "${kubectl_cnp} -n ${show_namespace} status ${selected}\n"
watch -c -n 1 ${kubectl_cnp} -n ${show_namespace} --color always status ${selected}
