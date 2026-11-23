
# Setup OpenShift Local (CRC)

The script sets up an OpenShift cluster on this machine with OpenShift Local (CRC)
and prints the result. It runs only if openshift_installed_locally="yes" in config.sh.
With "no" (OpenShift runs somewhere else) it prints SKIPPED and does nothing.

# What it does

- CRC already running: nothing is changed, only the login is checked
- CRC stopped or missing: crc setup, crc config set, crc start
  (cpus, memory and disk from crc_cpus, crc_memory, crc_disk_size in config.sh,
  cluster monitoring from enable_prometheus_monitoring, OpenShift version
  from crc_bundle: 4.22, because the EDB operator is not yet in the 5.0 catalogs)
- Logs in as kubeadmin and checks that the nodes are Ready
- The first start needs the Red Hat pull secret: OPENSHIFT_PULL_SECRET in the
  .credentials.sh file (git-ignored). It is written to a private temporary file
  for crc start and deleted right after.

```

crc status

crc config view

oc whoami

oc get nodes

```

# Remember

- The settings are applied only when the script starts CRC. To change them
  on a running CRC: crc stop, then run the script again.
- CRC must be installed before (it needs a Red Hat account).
- To remove the cluster: openshift_crc/stop_delete_openshift.sh
