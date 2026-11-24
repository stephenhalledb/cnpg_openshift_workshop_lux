#!/bin/bash

#crc delete -f
#crc cleanup

# See also ../00_setup_openshift_local.sh (follows openshift_installed_locally and
# the crc_* settings of config.sh, does not restart a CRC that is already running).
# This script always runs crc stop and uses its own fixed settings below.

# enable_prometheus_monitoring (config.sh) turns the OpenShift cluster monitoring on/off
. "$(dirname "$0")/../config.sh"
if [ "${enable_prometheus_monitoring}" == "yes" ]; then
  cluster_monitoring="true"
else
  cluster_monitoring="false"
fi

if [ ! -f "pull_secret.txt" ]; then
  echo ""
  echo "Error starting CRC."
  echo "Error: pull_secret.txt not found"
  echo "Please, create file with Red Hat secret."
  echo "Check this link: https://www.redhat.com/en/blog/install-openshift-local"
  exit 1
fi

crc setup
crc config set cpus 10
crc config set consent-telemetry no
crc config set memory 20480
crc config set preset openshift
crc config set disk-size 80
crc config set enable-cluster-monitoring ${cluster_monitoring}
crc stop
#crc config set disk-size 100

crc start -p ./pull_secret.txt

eval $(crc oc-env)
crc console --credentials

kubectl config set-context --current --namespace=openshift-operators

echo ""
echo ""
echo "eval $(crc oc-env)"
echo "oc login -u kubeadmin https://api.crc.testing:6443"
echo ""
if [ "${cluster_monitoring}" == "true" ]; then
  echo "Cluster monitoring is ON. After 06_prepare_cluster.sh, 10_install_cluster.sh enables"
  echo "the monitoring of the Postgres clusters (monitoring/06_openshift_monitoring.sh)."
  echo ""
fi
