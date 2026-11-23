#!/bin/bash
# Installs a single-pod MinIO (no operator) in the namespace minio-system.
# User, password and bucket name (S3_bucket_name) are taken from ../config.sh
. ../config.sh

minio_namespace="minio-system"

# The Job spec is immutable, remove a previous one so the script can be re-run
${kubectl_cmd} delete job minio-create-bucket -n ${minio_namespace} --ignore-not-found

envsubst '${ACCESS_KEY_ID} ${ACCESS_SECRET_KEY} ${S3_bucket_name}' < minio.yaml | ${kubectl_cmd} apply -f - || exit 1

${kubectl_cmd} rollout status deployment/minio -n ${minio_namespace} --timeout=300s || exit 1
${kubectl_cmd} wait --for=condition=complete job/minio-create-bucket -n ${minio_namespace} --timeout=300s || exit 1

console=$(${kubectl_cmd} get route minio-console -n ${minio_namespace} -o jsonpath='{.spec.host}')
api=$(${kubectl_cmd} get route minio-api -n ${minio_namespace} -o jsonpath='{.spec.host}')

printf "\nMinIO is ready\n"
printf "Console  : https://${console}\n"
printf "S3 API   : https://${api} (outside the cluster)\n"
printf "In-cluster endpoint for config.sh (s3_endpoint_url, no TLS needed):\n"
printf "  export s3_endpoint_url=\"http://minio-service.${minio_namespace}.svc.cluster.local:9000\"\n"
printf "Bucket   : ${S3_bucket_name}\n"
printf "User     : ${ACCESS_KEY_ID}\n"
printf "Password : ${ACCESS_SECRET_KEY}\n"
