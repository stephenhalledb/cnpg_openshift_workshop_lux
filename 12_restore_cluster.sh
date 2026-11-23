#!/bin/bash
. ./config.sh

#Doc
echo "12" > ./docs/docid

print_command "echo \"select pg_switch_wal()\" | ${kubectl_cnp} psql ${cluster_name}  -- -U postgres\n"
print_command "${kubectl_cmd} apply -f ./yaml/restore-cluster.yaml\n"

print_command "echo \"select pg_switch_wal()\" | ${kubectl_cnp} psql ${cluster_name} -- -U postgres\n"
sleep 3
# Folder of the restore cluster in the bucket: unique for each restore
export restore_server_name="${cluster_restore}-$(date +%Y%m%d-%H%M%S)"
print_info "WALs of ${cluster_restore} are archived in s3://${S3_bucket_name}/${restore_server_name}/\n"
envsubst < ./yaml/restore-cluster.yaml | ${kubectl_cmd} apply -n ${namespace} -f-

