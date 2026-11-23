#!/bin/bash
. ./config.sh

# Print whether the plugin is installed. Returns 0 if installed, 1 if not.
check_plugin() {
  if command -v ${kubectl_cnp} >/dev/null 2>&1; then
    print_info "Plugin ${kubectl_cnp}: INSTALLED ($(command -v ${kubectl_cnp}))\n"
    print_info "  $(${kubectl_cnp} version 2>&1 | head -1)\n"
    return 0
  else
    print_error "Plugin ${kubectl_cnp}: NOT INSTALLED\n"
    return 1
  fi
}

print_command "command -v ${kubectl_cnp} && ${kubectl_cnp} version\n"
if check_plugin; then
  exit 0
fi

if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
  print_warning "Install skipped (managed by the administrator): plugin_operator_minio_managed_by_admin=${plugin_operator_minio_managed_by_admin} in config.sh\n"
  exit 0
fi

print_command "https://github.com/EnterpriseDB/kubectl-cnp/raw/main/install.sh | \
  sh -s -- -b /usr/local/bin\n"

mkdir -p $HOME/bin

curl -sSfL \
  https://github.com/EnterpriseDB/kubectl-cnp/raw/main/install.sh | \
  sudo sh -s -- -b /usr/local/bin
  sh -s -- -b $HOME/bin

# Verify the result of the installation
hash -r
check_plugin
