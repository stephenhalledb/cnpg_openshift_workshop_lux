#!/bin/bash
# Deletes the archive of the restore cluster (${cluster_restore}: base backups and
# WALs) from the S3 storage: s3://<bucket>/<cluster_restore>/
# Why: the Barman Cloud Plugin refuses to archive in a folder that already contains
# WALs ("Expected empty archive"), so the archive must be removed when the restore
# cluster is deleted and created again with the same name (19_pitr_restore_line_one.sh).
# Run it only when the restore cluster is deleted: a running cluster would archive again.
# Only the folder of ${cluster_restore} is deleted, never the archive of ${cluster_name}.
# Exit code: 0 = deleted (or nothing to delete), 1 = error.

. ./config.sh

if ! command -v aws >/dev/null 2>&1; then
  print_error "aws CLI not found, cannot delete the archive (brew install awscli)\n"
  exit 1
fi

if [ -z "${cluster_restore}" ] || [ "${cluster_restore}" == "${cluster_name}" ]; then
  print_error "Refused: cluster_restore ('${cluster_restore}') is empty or equal to cluster_name\n"
  exit 1
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED=true PYTHONWARNINGS=ignore
args=()

if [ "${object_storage_type}" == "minio" ]; then
  # Same access as 00_setup_S3_storage.sh: the route of the MinIO API
  host=$(${kubectl_cmd} get route minio-api -n minio-system -o jsonpath='{.spec.host}' 2>/dev/null)
  if [ -z "${host}" ]; then
    print_error "Route minio-api not found in minio-system, cannot reach MinIO\n"
    exit 1
  fi
  args=(--endpoint-url "https://${host}" --no-verify-ssl)
  export AWS_ACCESS_KEY_ID="${ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${ACCESS_SECRET_KEY}"
else
  if [ ! -f ".aws.sh" ]; then
    print_error "File .aws.sh not found (see README), cannot reach AWS S3\n"
    exit 1
  fi
  . ./.aws.sh
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  [ -n "${AWS_SESSION_TOKEN}" ] && export AWS_SESSION_TOKEN
fi

target="s3://${object_storage_bucket}/${cluster_restore}/"
print_command "aws s3 rm ${target} --recursive\n"
if out=$(aws "${args[@]}" s3 rm "${target}" --recursive 2>&1); then
  n=$(echo "${out}" | grep -c 'delete:')
  print_info "Archive of ${cluster_restore} deleted: ${n} object(s) removed from ${target}\n"
else
  print_error "Archive of ${cluster_restore} NOT deleted:\n"
  printf "  %s\n" "$(echo "${out}" | grep -v -i warning | tail -3)"
  exit 1
fi
