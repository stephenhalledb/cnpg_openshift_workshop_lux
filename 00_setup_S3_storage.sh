#!/bin/bash
# Checks that the S3 object storage (used for backups and WALs) is available.
#   object_storage_type=minio : checks MinIO in minio-system, installs it with
#                               ./minio/install_minio.sh if missing
#   object_storage_type=aws   : checks that the AWS credentials and the bucket
#                               from config.sh can be used
# Installing MinIO is skipped when plugin_operator_minio_managed_by_admin is "yes" in
# config.sh (the check and its result are still printed).

. ./config.sh
. ./commands.sh

#Doc
echo "00" > ./docs/docid

minio_namespace="minio-system"

# S3 read/write test on the bucket from config.sh.
# $1 = endpoint URL (empty for AWS), $2 = access key id, $3 = secret key,
# $4 = session token (optional). A small object is written, read and deleted.
s3_usable() {
  local endpoint="$1" key="$2" secret="$3" token="$4"
  local object="cnpg-s3-check-$$.txt" args=() out

  if ! command -v aws >/dev/null 2>&1; then
    print_error "  aws CLI not found, cannot test the S3 storage (brew install awscli)\n"
    return 1
  fi
  [ -n "${endpoint}" ] && args=(--endpoint-url "${endpoint}" --no-verify-ssl)

  (
    export AWS_ACCESS_KEY_ID="${key}" AWS_SECRET_ACCESS_KEY="${secret}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    export AWS_EC2_METADATA_DISABLED=true PYTHONWARNINGS=ignore
    [ -n "${token}" ] && export AWS_SESSION_TOKEN="${token}"

    step() { # description, command...
      local d="$1"; shift
      if out=$("$@" 2>&1); then
        print_info "  ${d}: OK\n"
      else
        print_error "  ${d}: FAILED\n"
        printf "    %s\n" "$(echo "${out}" | grep -v -i -e warning -e '^$' | tail -3)"
        return 1
      fi
    }

    step "list bucket s3://${object_storage_bucket}" \
      aws "${args[@]}" s3 ls "s3://${object_storage_bucket}/" || exit 1
    echo "cnpg s3 check" > "${TMP}/${object}"
    step "write object" \
      aws "${args[@]}" s3 cp "${TMP}/${object}" "s3://${object_storage_bucket}/${object}" || { rm -f "${TMP}/${object}"; exit 1; }
    rm -f "${TMP}/${object}"
    step "delete object" \
      aws "${args[@]}" s3 rm "s3://${object_storage_bucket}/${object}" || exit 1
  )
}

# ---------------------------------------------------------------- MinIO
check_minio() {
  local ready
  ready=$(${kubectl_cmd} get deployment minio -n ${minio_namespace} \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)

  if [ "${ready}" == "1" ]; then
    print_info "MinIO deployment (${minio_namespace}): RUNNING\n"
    return 0
  fi
  print_error "MinIO deployment (${minio_namespace}): NOT RUNNING\n"
  return 1
}

setup_minio() {
  print_command "oc get deployment minio -n ${minio_namespace}\n"
  if ! check_minio; then
    if [ "${plugin_operator_minio_managed_by_admin}" == "yes" ]; then
      print_warning "Install skipped (managed by the administrator): plugin_operator_minio_managed_by_admin=${plugin_operator_minio_managed_by_admin} in config.sh\n"
      return 1
    fi
    if ! command -v envsubst >/dev/null 2>&1; then
      print_error "envsubst not found, needed by minio/install_minio.sh (brew install gettext)\n"
      return 1
    fi
    print_command "cd minio && ./install_minio.sh\n"
    (cd minio && ./install_minio.sh) || { print_error "MinIO installation FAILED\n"; return 1; }
    check_minio || return 1
  fi

  local host api_url svc_url
  host=$(${kubectl_cmd} get route minio-api -n ${minio_namespace} -o jsonpath='{.spec.host}' 2>/dev/null)
  api_url="https://${host}"
  svc_url="http://minio-service.${minio_namespace}.svc.cluster.local:9000"

  print_command "aws --endpoint-url ${api_url} s3 ls s3://${object_storage_bucket}/ (and write/delete test)\n"
  s3_usable "${api_url}" "${ACCESS_KEY_ID}" "${ACCESS_SECRET_KEY}" "" || return 1

  # The endpoint used by the Postgres clusters comes from config.sh
  if [ "${s3_endpoint_url}" == "${svc_url}" ] || [ "${s3_endpoint_url}" == "${api_url}" ]; then
    print_info "  s3_endpoint_url in config.sh: OK (${s3_endpoint_url})\n"
  else
    print_warning "  s3_endpoint_url in config.sh does not point to this MinIO: ${s3_endpoint_url}\n"
    print_warning "  Set it to: export s3_endpoint_url=\"${svc_url}\"\n"
  fi
  return 0
}

# ---------------------------------------------------------------- AWS
setup_aws() {
  print_command "aws s3 ls s3://${object_storage_bucket}/ (and write/delete test)\n"

  if [ ! -f ".aws.sh" ]; then
    print_error "  File .aws.sh not found. Create it with:\n"
    print_error "    export AWS_ACCESS_KEY_ID=\"<AWS_ACCESS_KEY_ID>\"\n"
    print_error "    export AWS_SECRET_ACCESS_KEY=\"<AWS_SECRET_ACCESS_KEY>\"\n"
    print_error "    export AWS_SESSION_TOKEN=\"<AWS_SESSION_TOKEN>\"\n"
    return 1
  fi
  . ./.aws.sh

  if command -v aws >/dev/null 2>&1; then
    local who
    if who=$(AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
        AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" AWS_EC2_METADATA_DISABLED=true \
        aws sts get-caller-identity --query Arn --output text 2>&1); then
      print_info "  AWS credentials: OK (${who})\n"
    else
      print_error "  AWS credentials: FAILED (expired or invalid, update .aws.sh)\n"
      printf "    %s\n" "$(echo "${who}" | tail -2)"
      return 1
    fi
  fi

  s3_usable "" "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${AWS_SESSION_TOKEN}"
}

# ---------------------------------------------------------------- Main
print_info "=======================================================\n"
print_info "S3 object storage (${object_storage_type}), bucket: ${object_storage_bucket}\n"
print_info "=======================================================\n"

case "${object_storage_type}" in
  minio) setup_minio; rc=$? ;;
  aws)   setup_aws;   rc=$? ;;
  *)     print_error "Unknown object_storage_type '${object_storage_type}' in config.sh (minio|aws)\n"; rc=1 ;;
esac

if [ ${rc} -eq 0 ]; then
  print_info "RESULT: S3 storage (${object_storage_type}) is AVAILABLE and usable\n"
else
  print_error "RESULT: S3 storage (${object_storage_type}) is NOT available\n"
fi
exit ${rc}
