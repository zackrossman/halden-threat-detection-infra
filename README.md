# halden-threat-detection-infra

Terraform for the Azure infrastructure behind **`halden-threat-detection`**, the
service that scores backup and restore activity for signs of ransomware and
other tampering across Halden's tenants.

This repository holds infrastructure only. **The application code lives in a
separate repository, `halden-threat-detection`**, and the two are owned by
different teams: the detection platform team writes the service, and this repo
is where the infrastructure for it is declared and reviewed. A release is a tag
built from the application repo and rolled out by bumping `image_tag` here.

This state manages the production deployment.

## What it deploys

| File | What it declares |
|------|------------------|
| `versions.tf` | Terraform and provider version pins, remote state backend |
| `providers.tf` | `azurerm` provider, plus a `kubernetes` provider borrowing the cluster's credentials |
| `variables.tf` | Every input, including the two sensitive ones |
| `aks.tf` | Lookups for the existing resource group and AKS cluster, and the `halden` namespace |
| `postgres.tf` | Azure Database for PostgreSQL flexible server, private DNS zone, `detection` database |
| `deployment.tf` | The runtime secret and the `halden-threat-detection` deployment |
| `service.tf` | The Kubernetes service that publishes the deployment |
| `outputs.tf` | Namespace, in-cluster DNS name, load balancer address, database FQDN |

The AKS cluster itself is not created here. The platform team provisions and
upgrades it in their own configuration; this repo looks it up with a data source
and rents a namespace on it.

## The service contract

`halden-threat-detection` speaks the **Halden internal service contract**, the
document Platform Engineering owns. Callers send `X-Halden-Gateway-Key` on every
request, carrying the shared key this configuration injects as
`HALDEN_GATEWAY_KEY`. The service reads that header on inbound requests.

The contract was written for **`halden-identity`**, the public-facing user and
tenant management service, which resolves this service at
`halden-threat-detection.halden.svc.cluster.local`. It is the caller the
detection platform team designed the API around.

## What the pods get

The `halden-threat-detection-runtime` secret carries `HALDEN_GATEWAY_KEY` and
`HALDEN_DATABASE_URL`; the service needs both to start. `HALDEN_ARTIFACT_DIR`
points at `/var/lib/halden/artifacts`, an `emptyDir` volume, because the
container filesystem is read-only. The container listens on port 8000, runs as
uid 10001, and answers `GET /healthz` for both probes.

## Network shape

The deployment listens on port 8000 and is published through a Kubernetes
service of type `LoadBalancer`, which gives it a public Azure address. That was
done during the migration off the legacy detection stack, so the platform team
could drive the API from the old collector hosts and from their workstations
while replaying traffic and comparing verdicts. `service.tf` carries the full
rationale, and the decision is meant to be revisited once the last collector is
cut over.

The database is configured differently. It has no public endpoint —
`public_network_access_enabled` is off, it sits on a delegated subnet, and the
cluster resolves it through a private DNS zone.

## Secrets

There are two: the gateway key and the PostgreSQL administrator password. Both
are variables marked `sensitive = true`, and neither has a default. Terraform
reads them from the environment:

```sh
export TF_VAR_halden_gateway_key="$(az keyvault secret show --vault-name CHANGE_ME --name threat-detection-gateway-key --query value -o tsv)"
export TF_VAR_postgres_administrator_password="$(az keyvault secret show --vault-name CHANGE_ME --name threat-detection-db-password --query value -o tsv)"
```

Keep secret values out of `terraform.tfvars`, out of this repo, and out of plan
files. `.gitignore` lists `*.tfvars` and `*.tfplan` for that reason. Both values
do land in Terraform state, which is why state lives in the remote backend with
Entra ID authentication rather than on anyone's laptop.

The values reach the pods through a `kubernetes_secret`. The pod template
carries the secret's resource version as an annotation, so rotating either value
rolls the fleet instead of leaving stale credentials in running pods.

## Running it

```sh
terraform init \
  -backend-config="resource_group_name=CHANGE_ME" \
  -backend-config="storage_account_name=CHANGE_ME" \
  -backend-config="container_name=CHANGE_ME" \
  -backend-config="key=threat-detection/production.tfstate"

cp terraform.tfvars.example terraform.tfvars   # then replace every CHANGE_ME
terraform plan
terraform apply
```

Deploying a new build is a one-line change:

```sh
terraform apply -var="image_tag=2026.08.19-a41c9e2"
```

Rolling updates use `maxUnavailable: 0` and a minimum of two replicas, so a
deploy does not drop requests.

## Database sizing

The flexible server runs with 35-day backup retention, geo-redundant backups,
and a zone-redundant standby. Sizing and storage come from `postgres_sku_name`
and `postgres_storage_mb`.
