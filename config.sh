#!/bin/bash

# =============================================================================
# 1. SETTINGS TO CHANGE
#    These are the only variables you normally have to change.
# =============================================================================

# --- Who are you -------------------------------------------------------------
export id="sh" #"$(oc whoami)"          # your name or id (used in the namespace and cluster names)
#   must be a valid Kubernetes name: lowercase a-z, 0-9 and "-" (an invalid value is
#   repaired in memory with a warning, see section 2)
export region="emea"                    # your region: emea, na or apj (used in the namespace name)

# --- Where does OpenShift run ------------------------------------------------
# Is OpenShift installed locally on this machine, with OpenShift Local (CRC)? [yes|no]
# yes = 00_setup_openshift_local.sh sets up and starts the CRC cluster (if it is
#       not already running) and logs in as kubeadmin. Size of the cluster: see
#       crc_cpus, crc_memory and crc_disk_size in section 2.
# no  = OpenShift runs somewhere else (remote or shared cluster): the script
#       does nothing. Log in with oc yourself.
export openshift_installed_locally="yes"

# --- Object storage for backups and WALs -------------------------------------
# Type of S3 object storage [minio|aws]
#   minio = MinIO on the OpenShift cluster (00_setup_S3_storage.sh checks/installs it)
#   aws   = AWS S3, the credentials are read from the .aws.sh file (see README)
export object_storage_type="minio"      # [minio|aws]
export S3_bucket_name="backups"                 # S3 bucket name

# MinIO credentials (used when object_storage_type is minio)
export ACCESS_KEY_ID="minio"
export ACCESS_SECRET_KEY="edb-workshop"
export ACCESS_SESSION_TOKEN=""          # only for AWS S3, if necessary

# Endpoint of the S3 storage used by the Postgres clusters.
# Default: the MinIO installed by this repo (inside the OpenShift cluster).
# Change it only if you use another MinIO.
export s3_endpoint_url="http://minio-service.minio-system.svc.cluster.local:9000"
#export s3_endpoint_url="https://minio-api-minio.apps.ocp.2lt49.sandbox2071.opentlc.com"

# --- Who installs the prerequisites ------------------------------------------
# Are MinIO, the kubectl-cnp plugin and the operator managed by an administrator? [yes|no]
# yes = the administrator installs them before this repo is used:
#       00_setup_S3_storage.sh, 01_install_plugin.sh and 02_install_cnpg_operator.sh
#       only check and print whether they are available (nothing is installed)
#       and 99_delete_env.sh does NOT remove MinIO
# no  = this repo installs them if they are missing (00_setup_S3_storage.sh, 01_install_plugin.sh 
#       , 02_install_cnpg_operator.sh)
#       and 99_delete_env.sh removes MinIO (if object_storage_type is minio)
# (if already installed, nothing is installed whatever the value)
export plugin_operator_minio_managed_by_admin="no"

# --- Monitoring --------------------------------------------------------------
# Prometheus monitoring of the Postgres clusters with the OpenShift (CRC) monitoring stack [yes|no]
# yes = openshift_crc/start_openshift.sh starts CRC with enable-cluster-monitoring=true,
#       and monitoring/06_openshift_monitoring.sh (called by 05_install_cluster.sh)
#       enables monitoring for user-defined projects and creates a PodMonitor
#       for the Postgres clusters in ${namespace}
# no  = start_openshift.sh starts CRC without cluster monitoring, and running
#       monitoring/06_openshift_monitoring.sh removes the PodMonitor and turns
#       monitoring for user-defined projects off
export enable_prometheus_monitoring="yes"


# =============================================================================
# 2. SETTINGS NORMALLY NOT CHANGED
#    Everything below is derived from the settings above or is a technical
#    default of the demo.
# =============================================================================

# --- Helper functions and temporary folder -----------------------------------
git_directory=`git rev-parse --show-toplevel`
. ${git_directory}/commands.sh

#. ./commands.sh

# Folder where the generated YAML files are written
export TMP=${HOME}/tmp
[ -d $TMP ] || mkdir $TMP
echo "Find the YAML-files in $TMP"

# --- Normalize the settings above --------------------------------------------
# The names in the settings (id, region, S3_bucket_name) must be valid names
# (see fix_name_variable in commands.sh). An invalid name is repaired in memory
# with a warning. A script stops here if a name cannot be repaired; an
# interactive shell is not closed.
{ fix_name_variables id region \
    && fix_name_variable S3_bucket_name "S3 bucket name"; } \
  || { [[ $- == *i* ]] && return 1; exit 1; }
# yes/no switches are case insensitive
export openshift_installed_locally=$(echo "${openshift_installed_locally}" | tr '[:upper:]' '[:lower:]')
export plugin_operator_minio_managed_by_admin=$(echo "${plugin_operator_minio_managed_by_admin}" | tr '[:upper:]' '[:lower:]')
export enable_prometheus_monitoring=$(echo "${enable_prometheus_monitoring}" | tr '[:upper:]' '[:lower:]')

# --- OpenShift Local (CRC) ---------------------------------------------------
# Used by 00_setup_openshift_local.sh when openshift_installed_locally is yes.
# They are applied only when CRC is started by the script: a CRC that is already
# running is not changed (crc stop, then run the script again to apply them).
export crc_cpus=10                       # CPUs of the CRC virtual machine (default 8)
export crc_memory=20480                  # memory in MiB (default 20480)
export crc_disk_size=80                  # disk in GiB (it can only grow) (default 80)
# OpenShift version of the CRC cluster = the CRC bundle file used for crc start.
# The EDB operator (package cloud-native-postgresql) is NOT in the OpenShift 5.0
# catalogs yet, so the demo is pinned to OpenShift 4.22. Empty = the default
# bundle of the installed crc (OpenShift 5.0 for crc 2.65). List: ls ~/.crc/cache
export crc_bundle="${HOME}/.crc/cache/crc_vfkit_4.22.14_arm64.crcbundle"
# The Red Hat pull secret (needed the first time CRC is created) is NOT in this
# file: put it in .credentials.sh as OPENSHIFT_PULL_SECRET (see README).

# --- Kubernetes environment --------------------------------------------------
export namespace="edb-${region}-${id}"   # k8s namespace (project) of the demo
export kubectl_cmd="oc"                  # command used to talk to the cluster
export kubectl_cnp="kubectl-cnp"         # CloudNativePG kubectl plugin

# --- Postgres clusters: names and size ---------------------------------------
export cluster_name="cluster-${id}"              # main cluster
export cluster_restore="cluster-restore-${id}"   # cluster created by the restore
# The names built from id and region must also be valid (for example not too long)
fix_name_variables namespace cluster_name cluster_restore || { [[ $- == *i* ]] && return 1; exit 1; }
export postgres_instances=3                      # number of instances (1 primary + replicas)
export postgres_cpu="0.1"                        # default value for workshop 0.1
export postgres_cpu_max="0.5"                    # default value for workshop 0.5

export postgres_memory="256Mi"                   # default value for workshop 256Mi
export postgres_memory_max="512Mi"               # default value for workshop 512Mi
export postgres_storage="512Mi"                  # default value for workshop 512Mi
export postgres_wal_storage="512Mi"              # default value for workshop 512Mi

# --- Postgres images ----------------------------------------------------------
# Using Docker repository

## List version images
## Login skopeo
## skopeo login docker.enterprisedb.com

## Operator
## skopeo list-tags docker://docker.enterprisedb.com/k8s/edb-postgres-for-kubernetes

## EDB Operator
## skopeo list-tags docker://docker.enterprisedb.com/k8s/edb-postgres-for-cloudnativepg

## Global cluster
## skopeo list-tags docker://docker.enterprisedb.com/k8s/edb-cloudnativepg-global-cluster

## EDB Postgres
## skopeo list-tags docker://docker.enterprisedb.com/k8s/postgresql

## EDB Postgres Extended
## skopeo list-tags docker://docker.enterprisedb.com/k8s/edb-postgres-extended

## EDB Postgres Advanced
## skopeo list-tags docker://docker.enterprisedb.com/k8s/edb-postgres-advanced

# ---
# EDB Postgres
export postgres_default_image="docker.enterprisedb.com/k8s/postgresql:17.6"          # first install
export postgres_upgrade_image="docker.enterprisedb.com/k8s/postgresql:17.7"          # minor upgrade
export postgres_major_upgrade_image="docker.enterprisedb.com/k8s/postgresql:18"

# EDB Postgres Extended
#export postgres_default_image="docker.enterprisedb.com/k8s/edb-postgres-extended:17.6"
#export postgres_upgrade_image="docker.enterprisedb.com/k8s/edb-postgres-extended:17.7"

# EDB Postgres Advanced Server
#export postgres_default_image="docker.enterprisedb.com/k8s/edb-postgres-advanced:17.6"
#export postgres_upgrade_image="docker.enterprisedb.com/k8s/edb-postgres-advanced:17.7"
# ---

# Major upgrade
export postgres_major_upgrade_image="docker.enterprisedb.com/k8s/postgresql:18.1"

# EPAS (EDB Postgres Advanced Server)
export epas_image="docker.enterprisedb.com/k8s/edb-postgres-advanced:17.7"
export epas_storage="512Mi"

# --- Object storage: derived values ------------------------------------------
export object_storage_bucket="${S3_bucket_name}"
export s3_destination_path="s3://${S3_bucket_name}/"

## S3
#export object_storage_bucket="${S3_bucket_name}"
#export s3_destination_path="s3://${S3_bucket_name}/"

# --- Transparent Data Encryption ---------------------------------------------
# TDE used
# Not yet implemented, required  postgres image of EDB Postgres Extended or EDB EPAS
export use_tde="N" # Y|N

# --- Affinity ----------------------------------------------------------------
# Affinity (useful when using Power machines)
# export affinity=$(cat <<EOF
#   affinity:
#     nodeAffinity:
#       requiredDuringSchedulingIgnoredDuringExecution:
#         nodeSelectorTerms:
#           - matchExpressions:
#               - key: machine_type
#                 operator: In
#                 values:
#                   - power
# EOF
#)
