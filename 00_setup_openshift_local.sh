#!/bin/bash
# Sets up an OpenShift Local (CRC) cluster on this machine, then prints the result.
# It runs only if openshift_installed_locally="yes" in config.sh; with "no"
# (OpenShift runs somewhere else) it prints that it is skipped and does nothing.
#
#   CRC already running : nothing is changed, only the login is checked
#   CRC stopped/missing : crc setup, crc config set (crc_cpus, crc_memory,
#                         crc_disk_size, enable_prometheus_monitoring), crc start
#                         (with the OpenShift version of crc_bundle, if set)
#   Always (if running) : login as kubeadmin and check that the nodes are Ready
#
# The first start needs the Red Hat pull secret: OPENSHIFT_PULL_SECRET in the
# .credentials.sh file (git-ignored, like EDB_SUBSCRIPTION_TOKEN). crc start
# reads the secret from a file, so it is written to a private temporary file
# (mode 600) for the start only and deleted right after.
# CRC itself must be installed: https://developers.redhat.com/products/openshift-local

. ./config.sh
[ -f ./.credentials.sh ] && . ./.credentials.sh

#Doc
echo "00_openshift_local" > ./docs/docid

crc_api_url="https://api.crc.testing:6443"

# crc_state: prints ready (VM and OpenShift running), stopped (VM exists but is
# not ready) or missing (no VM yet, or crc setup was never run)
crc_state() {
  local out vm openshift
  out=$(crc status 2>&1) || { echo missing; return; }
  vm=$(printf '%s\n' "${out}" | awk -F': *' '/^CRC VM:/ {print $2}')
  openshift=$(printf '%s\n' "${out}" | awk -F': *' '/^OpenShift:/ {print $2}')
  if [ -z "${vm}" ]; then
    echo missing
  elif [ "${vm}" = "Running" ] && [ "${openshift#Running}" != "${openshift}" ]; then
    echo ready
  else
    echo stopped
  fi
}

# Value of a crc config setting (empty if it is not set)
crc_config_value() {
  crc config view 2>/dev/null | awk -F': *' -v key="$1" '$1 ~ "- "key"( |$)" {print $2}'
}

# Applies the settings of config.sh. Only done before a start: cpus and memory
# of a running VM cannot be changed.
configure_crc() {
  local monitoring="false"
  [ "${enable_prometheus_monitoring}" == "yes" ] && monitoring="true"

  print_command "crc config set cpus ${crc_cpus} / memory ${crc_memory} / disk-size ${crc_disk_size} / enable-cluster-monitoring ${monitoring}\n"
  crc config set preset openshift >/dev/null \
    && crc config set cpus "${crc_cpus}" >/dev/null \
    && crc config set memory "${crc_memory}" >/dev/null \
    && crc config set disk-size "${crc_disk_size}" >/dev/null \
    && crc config set enable-cluster-monitoring "${monitoring}" >/dev/null || return 1

  # Do not decide the telemetry for the user if it is already set
  if [ -z "$(crc_config_value consent-telemetry)" ]; then
    crc config set consent-telemetry no >/dev/null
  fi
}

# Starts CRC. $1 = state (stopped|missing)
start_crc() {
  local state="$1" args=() secret_file="" status

  if [ -z "${OPENSHIFT_PULL_SECRET}" ] && [ "${state}" = "missing" ]; then
    print_error "  OPENSHIFT_PULL_SECRET is not set (needed to create the CRC cluster).\n"
    print_error "  Download the pull secret at https://console.redhat.com/openshift/create/local\n"
    print_error "  and add it to .credentials.sh (one line, between single quotes):\n"
    print_error "    export OPENSHIFT_PULL_SECRET='<content of the pull secret>'\n"
    return 1
  fi

  print_command "crc setup\n"
  crc setup || return 1
  configure_crc || return 1

  # crc start wants a file: private temporary copy of the secret, removed after the start
  if [ -n "${OPENSHIFT_PULL_SECRET}" ]; then
    secret_file=$(mktemp) && chmod 600 "${secret_file}" \
      && printf '%s' "${OPENSHIFT_PULL_SECRET}" > "${secret_file}" || { rm -f "${secret_file}"; return 1; }
    args=(-p "${secret_file}")
  fi

  # Pinned OpenShift version (crc_bundle in config.sh), default bundle of crc if empty
  if [ -n "${crc_bundle}" ]; then
    if [ ! -f "${crc_bundle}" ]; then
      print_error "  crc_bundle in config.sh not found: ${crc_bundle}\n"
      print_error "  Available bundles: ls ~/.crc/cache\n"
      [ -n "${secret_file}" ] && rm -f "${secret_file}"
      return 1
    fi
    args+=(-b "${crc_bundle}")
  fi

  print_command "crc start ${crc_bundle:+-b ${crc_bundle} }(takes several minutes)\n"
  crc start "${args[@]}"
  status=$?
  [ -n "${secret_file}" ] && rm -f "${secret_file}"
  return ${status}
}

# Logs in as kubeadmin on the CRC cluster (nothing to do if already logged in)
login_admin() {
  local password
  if [ "$(oc whoami 2>/dev/null)" = "kubeadmin" ] \
      && [ "$(oc whoami --show-server 2>/dev/null)" = "${crc_api_url}" ]; then
    print_info "  Login: already kubeadmin on ${crc_api_url}\n"
    return 0
  fi

  password=$(crc console --credentials 2>/dev/null \
    | sed -n 's/.*login -u kubeadmin -p \([^ ]*\) .*/\1/p')
  if [ -z "${password}" ]; then
    print_error "  Cannot read the kubeadmin password (crc console --credentials)\n"
    return 1
  fi
  print_command "oc login -u kubeadmin ${crc_api_url}\n"
  oc login -u kubeadmin -p "${password}" "${crc_api_url}" --insecure-skip-tls-verify=true >/dev/null \
    && print_info "  Login: kubeadmin on ${crc_api_url}\n"
}

# Prints the state of the cluster. Returns 1 if a node is not Ready.
check_cluster() {
  local nodes ready version
  nodes=$(oc get nodes --no-headers 2>/dev/null | wc -l | xargs)
  ready=$(oc get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l | xargs)
  version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)

  print_info "  OpenShift version: ${version:-unknown}\n"
  print_info "  Nodes Ready: ${ready}/${nodes}\n"
  print_info "  Console: $(crc console --url 2>/dev/null)\n"
  [ "${nodes}" -gt 0 ] && [ "${ready}" -eq "${nodes}" ]
}

# ---------------------------------------------------------------- Main
print_info "=======================================================\n"
print_info "OpenShift Local (CRC) on this machine\n"
print_info "=======================================================\n"

if [ "${openshift_installed_locally}" != "yes" ]; then
  print_info "openshift_installed_locally=\"${openshift_installed_locally}\" in config.sh: OpenShift Local is not set up by this repo.\n"
  print_info "RESULT: SKIPPED (log in to your OpenShift cluster with oc)\n"
  exit 0
fi

if ! command -v crc >/dev/null 2>&1; then
  print_error "crc not found. Install OpenShift Local first:\n"
  print_error "  https://developers.redhat.com/products/openshift-local/getting-started\n"
  print_error "RESULT: OpenShift Local is NOT available\n"
  exit 1
fi

state=$(crc_state)
print_info "CRC state: ${state}\n"

if [ "${state}" = "ready" ]; then
  print_info "CRC is already running, nothing to start.\n"
  # Settings are applied at the start only: say so if the monitoring differs
  wanted="false"; [ "${enable_prometheus_monitoring}" == "yes" ] && wanted="true"
  current=$(crc_config_value enable-cluster-monitoring); current=${current:-false}
  if [ "${current}" != "${wanted}" ]; then
    print_warning "  enable_prometheus_monitoring in config.sh needs enable-cluster-monitoring=${wanted},\n"
    print_warning "  CRC has ${current}. Run crc stop and this script again to apply it.\n"
  fi
else
  start_crc "${state}" || { print_error "RESULT: OpenShift Local is NOT available (start failed)\n"; exit 1; }
fi

# oc from CRC if there is no oc in the PATH
command -v oc >/dev/null 2>&1 || eval "$(crc oc-env)"

if login_admin && check_cluster; then
  print_info "RESULT: OpenShift Local (CRC) is RUNNING and you are logged in as kubeadmin\n"
else
  print_error "RESULT: OpenShift Local (CRC) is NOT ready (see the messages above)\n"
  exit 1
fi
