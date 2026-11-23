
# Changes
The purpose of this files is to documenst my installation and use of this demo


1. need to put Action point with icon
   1. Action action with the code to run
   2. expected results
   3. commun problemes
   for example 
   - change the `config.sh`
   - `create .credentials` 
   - run `./env.sh`
   - run `Set_context.sh`
2. where is step to make sure that the S3 storage ready
   I ran the inslatll minio but image on quai was an issue
   replace in `minio_crc.yaml` in line 48 to `cgr.dev/chainguard/minio:latest`
3. how to get pgadmin running and connect to
   - it could be from my local pgadmin
   - it could be from a pgadmin that runs in the openshift cluster or dev env.
4. Get the graphana display the telemetry from the postgress cluster 
5. Change the ressoucre of the postgres cluster
  resources:
    requests:
      memory: "$postgres_memory"
      cpu: "$postgres_cpu"
    limits:
      memory: "$postgres_memory_max"
      cpu: "$postgres_cpu_max"