# Purpose of the demo
In this demo I'll show you how to create a PostgreSQL cluster with the Red Hat OpenShift operator called EDB CloudNativePG.
The features that I want to show you are:
- Kubernetes plugin install
- EDB Postgres for Kubernetes operator install
- Postgres cluster install
- Insert data in the cluster
- Switchover (promote)
- Failover
- Backup & Recovery (in a S3 Minio platform)
- Scale out/down
- Rolling updates (minor and major)
- Point In Time Recovery (PITR)
- Fencing
- Replication slots (for HA)
- Monitoring (scripts)
- Operator upgrade

# Infrastructure
The demo runs on Red Hat OpenShift 4.x. You need the `oc` CLI (and `jq`, optional, to format JSON log outputs). Choose where OpenShift runs:

- **Option 1, locally**: OpenShift Local (CRC) on your machine, set up by `00_setup_openshift_local.sh` (`openshift_installed_locally="yes"`). See [Option 1](#option-1-locally-with-openshift-local-crc).
- **Option 2, dedicated OpenShift cluster**: a cluster that already exists, for example one set up by an administrator (`openshift_installed_locally="no"`). See [Option 2](#option-2-dedicated-openshift-cluster-set-up-by-an-admin).

In both cases check the [settings](#before-you-start-both-options) first, then run the [prerequisite scripts](#prerequisite-scripts-both-options) (`00` to `03`). The demo flow starts at `04-prepare-cluster.sh`.

## Before you start (both options)

### Settings in config.sh
Modify the `config.sh` file with your parameters (section 1 of the file):
- `id` : with your name or id (must be a valid Kubernetes name: lowercase letters, digits and `-`. If not, `config.sh` repairs it in memory, for example `SH` becomes `sh`, and prints a warning until you fix the value in `config.sh`)
- `region`: region in which you deploy your clusters: `[emea|na|apj]` (same rule as `id`)
- `openshift_installed_locally`: `yes` (default) if OpenShift runs on this machine with OpenShift Local (CRC), `no` if OpenShift runs somewhere else. `00_setup_openshift_local.sh` follows it (the CRC size is set by `crc_cpus`, `crc_memory` and `crc_disk_size`)
- `plugin_operator_minio_managed_by_admin`: `yes` if an administrator installs MinIO, the `kubectl-cnp` plugin and the operator before you use this repo: the scripts only check and print whether they are available, and `99_delete_env.sh` does not remove MinIO. `no` (default): the scripts install them if they are missing (MinIO only if `object_storage_type` is `minio`) and `99_delete_env.sh` removes MinIO
- `enable_prometheus_monitoring`: `yes` (default) turns on Prometheus monitoring of the Postgres clusters with the OpenShift monitoring stack (see [Monitoring with Prometheus](#monitoring-with-prometheus-on-openshiftcrc)), `no` turns it off
- `S3_bucket_name`: Your S3 bucket where you store your backups and Postgres wals (lowercase letters, digits and `-`, an invalid name is repaired in memory with a warning).
- `object_storage_type` to `minio` or `aws`
- `ACCESS_KEY_ID`
- `ACCESS_SECRET_KEY`
- `ACCESS_SESSION_TOKEN` if necessary (only for AWS S3)

### EDB Repo
You need an EDB token to access to the EDB private repository to be able to download
the EDB images (PostgreSQL, EDB Postgres Extended and/or EDB Postgres Advanced Server).
Create a file called `.credentials.sh` with your token:
```
export EDB_SUBSCRIPTION_TOKEN="<your-token>"
```

### AWS Credentials
If you are using AWS as object storage, create a file `.aws.sh` with this information:
```
export AWS_ACCESS_KEY_ID="<AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<AWS_SECRET_ACCESS_KEY>"
export AWS_SESSION_TOKEN="<AWS_SESSION_TOKEN>"
```

## Option 1: Locally with OpenShift Local (CRC)
Use it to run the demo on your own machine. You need:
- OpenShift Local (`crc`) installed: https://developers.redhat.com/products/openshift-local/getting-started
- A Red Hat account, to download the pull secret
- A machine with enough resources for the CRC virtual machine (defaults: 10 CPUs, 20480 MiB of memory and 80 GiB of disk, see `crc_cpus`, `crc_memory`, `crc_disk_size` in `config.sh`)

### OpenShift pull secret (only for OpenShift Local)
Needed only when the CRC cluster does not exist yet (the first `crc start`).
Download your pull secret at https://console.redhat.com/openshift/create/local and add it to the same `.credentials.sh` file (git-ignored), as one line between single quotes:
```
export OPENSHIFT_PULL_SECRET='<content of the pull secret>'
```

### Start the cluster
Set `openshift_installed_locally="yes"` in `config.sh`, then run:
```
./00_setup_openshift_local.sh
```
- If CRC is already running nothing is changed, only the login is checked.
- If it is stopped or missing it runs `crc setup`, applies `crc_cpus`, `crc_memory`, `crc_disk_size` and `enable_prometheus_monitoring` with `crc config set`, and runs `crc start`.
- The OpenShift version is set by `crc_bundle` in `config.sh` (pinned to OpenShift 4.22.14). Do not leave it empty with crc 2.65 or later: the default bundle is OpenShift 5.0, and its `certified-operators` catalog does not contain the EDB operator (`cloud-native-postgresql`), so `02_install_cnpg_operator.sh` fails with `packagemanifests ... not found`. The bundles on this machine: `ls ~/.crc/cache`.
- The first start reads the pull secret from `OPENSHIFT_PULL_SECRET` in `.credentials.sh`. It is written to a private temporary file for `crc start` and deleted right after.
- It logs in as `kubeadmin` and checks that the nodes are Ready.
- The settings are applied only when the script starts CRC: to change them on a running CRC, run `crc stop` and the script again.
- To remove the cluster: `openshift_crc/stop_delete_openshift.sh`.

Then run the [prerequisite scripts](#prerequisite-scripts-both-options). With the default `plugin_operator_minio_managed_by_admin="no"` they install MinIO, the plugin and the operator on your CRC.

### Open the OpenShift console (web UI)
When CRC is running, open the console in your browser:
```
crc console
```
or go to https://console-openshift-console.apps-crc.testing (accept the browser warning: CRC uses a self-signed certificate).
- Log in as the administrator with the user `kubeadmin`. Show the password with:
  ```
  crc console --credentials
  ```
  (`00_setup_openshift_local.sh` uses the same password to log in `oc`.)
- `crc console --url` only prints the URL.
- Useful pages for the demo: *Workloads > Pods* and *Home > Projects* (your namespace is `edb-<region>-<id>`), *Operators > Installed Operators* (EDB Postgres for Kubernetes) and, with monitoring on, *Observe > Targets* and *Observe > Metrics*.

## Option 2: Dedicated OpenShift cluster (set up by an admin)
Use it when the OpenShift cluster already exists (a shared, remote or sandbox cluster). Start here:
1. Log in to the cluster with `oc login <api url>`. Installing the operator, MinIO and the Prometheus monitoring needs `cluster-admin`; without it set `enable_prometheus_monitoring="no"` and ask the administrator to install the rest.
2. Set `openshift_installed_locally="no"` in `config.sh`. `00_setup_openshift_local.sh` then prints that it is skipped and does nothing (you can run it anyway).
3. Ask the administrator what is already installed: MinIO (or the S3 storage), the `kubectl-cnp` plugin and the EDB Postgres for Kubernetes operator.
   - Installed by the administrator: set `plugin_operator_minio_managed_by_admin="yes"`. The scripts only check and print the result, and `99_delete_env.sh` does not remove MinIO.
   - Installed by you (you have `cluster-admin`): keep `plugin_operator_minio_managed_by_admin="no"`, the scripts install what is missing.
4. Set the S3 storage (`object_storage_type`, `s3_endpoint_url`, credentials) as the administrator gives it to you.
5. Run the [prerequisite scripts](#prerequisite-scripts-both-options) to check that everything is available.

## Prerequisite scripts (both options)
Run them in this order, from the repo folder. Each one prints the result.
```
00_setup_openshift_local.sh   (option 1 only, skipped when openshift_installed_locally="no")
00_setup_S3_storage.sh
01_install_plugin.sh
02_install_cnpg_operator.sh
03_check_cnpg_operator_runs.sh
03b_install_barman_cloud_plugin.sh
```
- `00_setup_S3_storage.sh`: checks that the S3 storage is available and prints the result. With `object_storage_type="minio"` it checks the MinIO in the `minio-system` namespace and installs it with `minio/install_minio.sh` if it is missing and `plugin_operator_minio_managed_by_admin="no"`. With `aws` it checks that the credentials in `.aws.sh` and the bucket can be used. In both cases it lists the bucket and writes/deletes a small test object. Requires the `aws` CLI (and `envsubst` to install MinIO). It also checks that `s3_endpoint_url` in `config.sh` points to the MinIO.
- `01_install_plugin.sh`: checks if the `kubectl-cnp` plugin is installed and prints the result. It installs the plugin only if it is missing and `plugin_operator_minio_managed_by_admin="no"`.
- `02_install_cnpg_operator.sh`: checks if the operator is installed and healthy and prints the result. It installs the operator only if it is missing and `plugin_operator_minio_managed_by_admin="no"`, then waits up to 2 minutes and prints the final status. Before the install it checks the pull secret `postgresql-operator-pull-secret` in `openshift-operators` and, if it is missing, creates it by running `connect_edb_token.sh` (user `k8s`, password `EDB_SUBSCRIPTION_TOKEN` from `.credentials.sh`): without it the operator image cannot be pulled and the pod stays in `ImagePullBackOff`. It stops with a message if the secret cannot be created (for example the token is not set). An existing secret is not replaced: after a token change run `./connect_edb_token.sh` yourself.
- `connect_edb_token.sh`: creates (or replaces) the pull secret `postgresql-operator-pull-secret` with `EDB_SUBSCRIPTION_TOKEN`, then runs `docker login docker.enterprisedb.com` if docker is installed (a failed login is only a warning). Exit code 1 if the token is not set or the secret cannot be created.
- `03_check_cnpg_operator_runs.sh`: shows the operator deployment (checks that it runs).
- `03b_install_barman_cloud_plugin.sh`: backups and WAL archiving of the clusters use the [Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/) (the in-tree `barmanObjectStore` is deprecated). The script checks cert-manager (a requirement of the plugin) and the plugin and installs what is missing if `plugin_operator_minio_managed_by_admin="no"`: cert-manager `cert_manager_version` and the plugin `barman_cloud_plugin_version` (both in `config.sh`). The plugin must run in the namespace of the operator, so the release manifest (made for `cnpg-system`) is installed in `openshift-operators`. Not to be confused with the `kubectl-cnp` kubectl plugin of `01_install_plugin.sh`. The bucket settings are in an `ObjectStore` resource (`yaml/objectstore.yaml`, `yaml/objectstore-aws.yaml` for AWS) created by `05_install_cluster.sh` before the cluster; the clusters reference it in `spec.plugins`, and `yaml/backup.yaml` uses `method: plugin`.

## MinIO web UI
Only when `object_storage_type="minio"`. MinIO stores the backups and WALs in the bucket `S3_bucket_name`; its console shows them.
- **Open** the route of the console (namespace `minio-system`). On CRC it is https://minio-console-minio-system.apps-crc.testing . To get the URL on any cluster:
  ```
  oc get route minio-console -n minio-system -o jsonpath='https://{.spec.host}{"\n"}'
  ```
- **Log in** with the user `ACCESS_KEY_ID` and the password `ACCESS_SECRET_KEY` from `config.sh` (defaults: `minio` / `edb-workshop`). Accept the browser warning on CRC (self-signed certificate).
- **Look at** *Object Browser > your bucket* (default `backups`) to see the backups and WAL files after `10_backup_cluster.sh`.
- **No route?** Forward the console port and open http://localhost:9090 :
  ```
  oc port-forward svc/minio-service 9090:9090 -n minio-system
  ```
- The route `minio-api-minio-system.apps-crc.testing` is the S3 API (for `aws s3`), not a UI.
- If an administrator installed MinIO (`plugin_operator_minio_managed_by_admin="yes"`), the namespace and route names can differ: ask for the console URL.

# Demo namespace structure
```
Namespaces

├── edb-emea-user1
│   ├─ cluster-user1
│   ├─ cluster-user1-17
│   ├─ cluster-restore
├── edb-emea-user2
│   ├─ cluster-user2
│   ├─ cluster-user2-17
│   ├─ cluster-restore
├── edb-na-user3
│   ├─ cluster-user3
├── edb-na-user4
│   ├─ cluster-user4
│   ├─ cluster-user4-17
│   ├─ cluster-restore
├── edb-apj-user5
└── edb-apj-user6
    ├─ cluster-user6
    ├─ cluster-user6-17
    └─ cluster-restore
```

# Dashboard
File `env.sh` show all the env variables created to manage
the PostgreSQL clusters in Red Hat OpensShift. This is an example:
```
./env.sh
----------------------------------------------------------------------------------------------
⎈ Kubernetes environment ⎈
----------------------------------------------------------------------------------------------
Context
├─ Current name            : default/api-ocp4-multiarch-acmi-fr:6443/kube:admin
├─ Current cluster         : api-ocp4-multiarch-acmi-fr:6443
└─ Current namespace       : edb-emea-sergio
Pods
└─ Sum of pod CPU's        : 1.5 / 120
Nodes
├─ Total K8s nodes         : 6
└─ Total of CPU's (workers): 120
Kubernetes Namespace       : edb-emea-sergio

----------------------------------------------------------------------------------------------
PostgreSQL Cluster configuration
----------------------------------------------------------------------------------------------
Postgres Cluster Name      : cluster-sergio
Postgres Instances         : 3
Postgres CPU's             : 0.5
Postgres Memory            : 512Mi
Postgres storage           : 512Mi
Postgres WAL storage       : 512Mi
Postgres default image     : docker.enterprisedb.com/k8s/edb-postgres-advanced:17.6
Postgres upgrade image     : docker.enterprisedb.com/k8s/edb-postgres-advanced:17.7

----------------------------------------------------------------------------------------------
Object Storage
----------------------------------------------------------------------------------------------
Object Storage type        : aws
Object Storage bucket      : sergio1-bucket
Destination path           : s3://sergio1-bucket/
Endpoint                   : https://minio-api-minio.apps.cluster-bdb5x.bdb5x.sandbox789.opentlc.com

----------------------------------------------------------------------------------------------
Transparent Data Encryption (TDE)
----------------------------------------------------------------------------------------------
Using TDE (in progress)    : N
```

# Demo flow
The infrastructure scripts `00` to `03` are described in [Infrastructure](#infrastructure). Execute the demo commands in the correct order, starting from `04-prepare-cluster.sh`:

```
04-prepare-cluster.sh
05_install_cluster.sh
06_show_status.sh
07_insert_data.sh
08_promote.sh
09_upgrade.sh
```
`06_show_status.sh` shows the status of the main cluster (`cluster_name` in `config.sh`). `show_status.sh` does the same for any cluster: it lists the clusters of the default namespace (the current `oc` project) and asks which one to display (`./show_status.sh <cluster>` skips the question; with only one cluster it is chosen without asking).
# Backup and Recovery
```
10_backup_cluster.sh
11_backup_describe.sh
12_restore_cluster.sh
13_check_restore.sh
```
The restore takes a few minutes (the new cluster first fetches the backup and the WAL files from the object storage). `13_check_restore.sh` waits until the restore cluster is up and running, prints a message while it waits, and then shows the restored data. It stops with an error if the cluster does not exist (run `12_restore_cluster.sh` first) or is not ready after 600 seconds (change it with `RESTORE_WAIT_TIMEOUT=<seconds> ./13_check_restore.sh`).
# Failover
```
14_failover.sh
```
# Scale out and down
One script. Without a parameter it shows the current number of instances and asks for the new number (`q` quits). The number must be at least 1 and different from the current one. With parameters it does not ask (with 3 instances, `out` gives 4 and `in` gives 2, as in the demo):
```
15_scale.sh
15_scale.sh 5
15_scale.sh out
15_scale.sh in
15_scale.sh out 5
```
# PITR (Point in Time Recovery)
```
16_pitr_insert_two_lines.sh
17_pitr_backup.sh
18_pitr_insert_new_line.sh
19_pitr_restore_line_one.sh
```
# Major Upgrade
By copy (creates a new cluster with the new version) and in place:
```
20_major_upgrade_by_copy.sh
21_verify_data_migrated.sh
24_major_upgrade_in_place.sh
```
# Fencing
One script. Without a parameter it asks in the terminal: `a) fence` or `b) unfence` a standby instance of the cluster (`q` quits). With `on` (fence) or `off` (unfence) it does not ask:
```
22_fencing.sh
22_fencing.sh on
22_fencing.sh off
```
# Hibernation
One script. Without a parameter it asks in the terminal: `a) hibernate` or `b) resume` the cluster (`q` quits). With `on` (hibernate) or `off` (resume) it does not ask. When hibernating, the script waits until the cluster is HIBERNATED (the condition `k8s.enterprisedb.io/hibernation` is True and all its pods are gone, the PVCs are kept) and prints a message every 5 seconds while it waits. It stops with an error after 300 seconds (change it with `HIBERNATION_WAIT_TIMEOUT=<seconds> ./23_hibernation.sh on`):
```
23_hibernation.sh
23_hibernation.sh on
23_hibernation.sh off
```

# Fencing and Hibernation
```
./22_fencing.sh on
./22_fencing.sh off
./23_hibernation.sh on
./23_hibernation.sh off

```
# Monitoring with Prometheus on OpenShift/CRC
The variable `enable_prometheus_monitoring` in `config.sh` turns the monitoring of the Postgres clusters on (`yes`, default) or off (`no`). It uses the Prometheus that comes with OpenShift, not the Helm based scripts `monitoring/01` to `05` (those install a second Prometheus that conflicts with OpenShift, and `monitoring/99_remove_monitoring.sh` deletes the Prometheus CRDs of OpenShift: do not use them on OpenShift/CRC).

- `00_setup_openshift_local.sh` and `openshift_crc/start_openshift.sh` set `crc config set enable-cluster-monitoring true|false` from the variable (takes effect at `crc start`; the first one only when it starts CRC and warns if a running CRC has another value).
- `monitoring/06_openshift_monitoring.sh` (called at the end of `05_install_cluster.sh` when `yes`):
  - `yes`: enables monitoring for user-defined projects (ConfigMap `cluster-monitoring-config`, needs cluster-admin) and creates the PodMonitor `postgres-clusters` in your namespace. It selects every pod with the label `k8s.enterprisedb.io/cluster`, so the restored and upgraded clusters are included.
  - `no`: deletes the PodMonitor and turns monitoring for user-defined projects off.
- Check in the OpenShift console: *Observe > Targets* and *Observe > Metrics* (for example the query `cnp_collector_up`).
- `99_delete_env.sh` removes the PodMonitor with the namespace but leaves the cluster-wide monitoring setting as it is.
- Monitoring uses more memory. Cluster monitoring needs a CRC restart to be turned on or off.

# Delete clusters
Deletes the clusters and the demo namespace. If `object_storage_type="minio"` it also removes MinIO (namespace `minio-system`), **including the backups stored in it**, unless `plugin_operator_minio_managed_by_admin="yes"`.
```
99_delete_env.sh
```
# cnpg_openshift_workshop_ffm
