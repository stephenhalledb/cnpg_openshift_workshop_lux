#!/bin/bash

. ./config.sh

${kubectl_cmd} delete cluster.postgresql.k8s.enterprisedb.io ${cluster_name}
${kubectl_cmd} delete cluster.postgresql.k8s.enterprisedb.io ${cluster_restore}
${kubectl_cmd} delete cluster.postgresql.k8s.enterprisedb.io ${cluster_name}-major
${kubectl_cmd} delete namespace ${namespace}

# Remove MinIO (namespace minio-system, including the backups stored in it)
# only if it is the object storage of this demo and it is not managed by the
# administrator (plugin_operator_minio_managed_by_admin in config.sh)
minio_removed="no (object_storage_type=${object_storage_type})"
if [ "${object_storage_type}" == "minio" ]; then
  if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
    minio_removed="no (managed by the administrator)"
  else
    print_command "cd minio && ./uninstall_minio.sh\n"
    (cd minio && ./uninstall_minio.sh)
    minio_removed="yes (namespace minio-system)"
  fi
fi

print_info "======================================================\n"
print_info "Your demo environment has been deleted.\n"
print_info "Namespace: $namespace\n"
print_info "Clusters: ${cluster_name} and ${cluster_restore}\n"
print_info "MinIO removed: ${minio_removed}\n"
print_info "======================================================\n"
