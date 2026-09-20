# Agent Relay on kind

These manifests reproduce the Compose API and PostgreSQL services. Apply all
YAML files to the same namespace. They use the current namespace by default.

- `database-secret.yaml`: local database credentials and the API connection URL.
- `postgres-pvc.yaml`: a 1 GiB claim using the default StorageClass.
- `postgres.yaml`: a single PostgreSQL Deployment and the `postgres` Service.
- `api.yaml`: the API Deployment and its internal `agent-relay-api` Service.

The API connects to `postgres:5432/agent_relay` using psycopg. An init container
waits for PostgreSQL before starting the app. PostgreSQL readiness uses
`pg_isready`; API readiness calls `/ready`, which queries the database tables.
The API's `/health` liveness check does not depend on database availability.

PostgreSQL mounts `postgres-data` at `/var/lib/postgresql/data`, with its database
files under `pgdata`. Replacing the database pod reuses the claim. The single
replica and Recreate strategy prevent overlapping database pods during updates.
Storage survives pod replacement, but deleting the claim or the kind cluster
can delete the data. Existing Compose data is not automatically transferred.

## Before deploying (commands are not run by these manifests)

The API requires `agent-relay:local` to be present on the kind node. Its pull
policy is Never, so Kubernetes will not attempt to download this local image.
The earlier `agent-relay:local` build predates PostgreSQL support; the Compose
build used a separate image tag. Refresh the requested tag from current source
and load it before deployment:

```bash
docker build -t agent-relay:local .
kind load docker-image agent-relay:local --name agent-relay
```

When ready to deploy:

```bash
kubectl --context kind-agent-relay apply -f k8s/
kubectl --context kind-agent-relay rollout status deployment/postgres
kubectl --context kind-agent-relay rollout status deployment/agent-relay-api
```

Both Services are internal ClusterIP Services. For browser access without
conflicting with Compose on host port 8000:

```bash
kubectl --context kind-agent-relay port-forward service/agent-relay-api 8001:8000
```

Then open http://localhost:8001/. Credentials in the Secret are local development
values matching Compose. No application worker is started by these manifests.
