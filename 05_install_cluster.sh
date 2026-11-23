#!/bin/bash

. ./config.sh
. ./env.sh

#Doc
echo "05" > ./docs/docid

if [[ $? -eq 1 ]]; then
    echo "Error occurred. Please fix the problem."
    exit 1
fi

# Create namespace if does not exists
. ./create_namespace.sh

# ObjectStore of the Barman Cloud Plugin (bucket settings for backups and WALs),
# it must exist before the cluster. Needs the minio-creds secret (04-prepare-cluster.sh).
objectstore_yaml="./yaml/objectstore.yaml"
[ "${object_storage_type}" == "aws" ] && objectstore_yaml="./yaml/objectstore-aws.yaml"
print_command "${kubectl_cmd} apply -n ${namespace} -f ${objectstore_yaml}\n"
envsubst < ${objectstore_yaml} | ${kubectl_cmd} apply -n ${namespace} -f-

print_command "${kubectl_cmd} apply -n ${namespace} -f ./yaml/cluster-sample.yaml\n"

envsubst < ./yaml/cluster-sample.yaml | ${kubectl_cmd} apply -n ${namespace} -f-

# Prometheus monitoring (enable_prometheus_monitoring in config.sh).
# Not fatal: the cluster is installed even if the monitoring setup fails.
if [ "${enable_prometheus_monitoring}" == "yes" ]; then
  print_command "./monitoring/06_openshift_monitoring.sh\n"
  ./monitoring/06_openshift_monitoring.sh || print_warning "Monitoring setup failed, see the messages above\n"
  echo "05" > ./docs/docid
fi

