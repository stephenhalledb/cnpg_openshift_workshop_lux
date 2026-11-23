
# Monitoring with Prometheus

The Postgres clusters are monitored with the Prometheus that comes with
OpenShift. The variable enable_prometheus_monitoring in config.sh turns it
on (yes) or off (no).

# Steps

- start_openshift.sh: CRC is started with enable-cluster-monitoring=true
- monitoring for user-defined projects is enabled (needs cluster-admin)
- a PodMonitor selects the pods with the label k8s.enterprisedb.io/cluster

```

oc get pods -n openshift-user-workload-monitoring

oc get podmonitor -n <namespace>

```

# ConfigMap

```

apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true

```

# PodMonitor

```

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: postgres-clusters
spec:
  selector:
    matchExpressions:
    - key: k8s.enterprisedb.io/cluster
      operator: Exists
  podMetricsEndpoints:
  - port: metrics

```

# Check

In the OpenShift console: Observe > Targets, Observe > Metrics
Query: cnp_collector_up

# Off

With enable_prometheus_monitoring="no" the script deletes the PodMonitor
and turns monitoring for user-defined projects off.

# Doc
[EDB monitoring](https://www.enterprisedb.com/docs/postgres_for_kubernetes/latest/monitoring/)
[OpenShift user workload monitoring](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html/monitoring/enabling-monitoring-for-user-defined-projects)

