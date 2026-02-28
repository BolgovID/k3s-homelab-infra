# Homelab k3s GitOps Repository

This repository is reorganized for maintainability and safer operations.

## What This Repository Deploys

- Platform:
  - Namespaces
  - PriorityClasses
  - cert-manager ClusterIssuer + wildcard cert
  - Argo CD (via k3s `HelmChart` CR)
  - Reloader
- Apps:
  - PostgreSQL + pgAdmin
  - MinIO (via k3s `HelmChart` CR)
  - Postfix SMTP relay (`mail` namespace)
  - Argo CD Applications:
    - GitLab (GitLab chart)
    - GitLab Runner (gitlab-runner chart)
    - Redis (Bitnami chart)
    - Harbor (Bitnami chart)

## Repository Structure

- `clusters/homelab/`: top-level cluster composition (kustomize entrypoint)
- `platform/`: cluster-wide services and base infra
- `apps/`: workload manifests and Argo applications
- `secrets/templates/`: committed secret templates (no real secrets)
- `secrets/live/`: local-only real secret manifests (gitignored)
- `scripts/`: bootstrap and deploy helpers
- `legacy/`: previous unstructured manifests kept for reference

## Security Model

No real credentials are stored in tracked manifests.

Sensitive values must be provided through Kubernetes Secrets in `secrets/live/`:

- Cloudflare API token (`cloudflare-api-token-secret`)
- PostgreSQL auth (`postgres-auth`)
- pgAdmin auth (`pgadmin-auth`)
- MinIO root creds (`minio-root-user`)
- Redis auth (`redis-auth`)
- Harbor core env secret (`harbor-core-envvars`)
- Harbor internal shared secret (`harbor-internal`)
- Argo CD runtime secret (`argocd-secret`, includes `server.secretkey` and plaintext `admin.password`)
- Postfix relay auth (`postfix-relay-auth`)
- GitLab bootstrap/runtime secrets (`initial-admin-password`, `postgres-secret`, `gitlab-redis`, `minio-credentials`, `s3-credentials`, `fake-mail-password`)
- GitLab Runner registration/auth/cache secret (`dev-gitlab-runner`)

## Required Secret Setup

1. Copy template secrets to `secrets/live/`:

```bash
cp secrets/templates/cert-manager/cloudflare-api-token.secret.example.yaml secrets/live/cloudflare-api-token-secret.yaml
cp secrets/templates/postgres/postgres-auth.secret.example.yaml secrets/live/postgres-auth.yaml
cp secrets/templates/postgres/pgadmin-auth.secret.example.yaml secrets/live/pgadmin-auth.yaml
cp secrets/templates/minio/minio-root-user.secret.example.yaml secrets/live/minio-root-user.yaml
cp secrets/templates/redis/redis-auth.secret.example.yaml secrets/live/redis-auth.yaml
cp secrets/templates/harbor/harbor-core-envvars.secret.example.yaml secrets/live/harbor-core-envvars.yaml
cp secrets/templates/harbor/harbor-internal.secret.example.yaml secrets/live/harbor-internal.yaml
cp secrets/templates/argocd/argocd-secret.secret.example.yaml secrets/live/argocd-secret.yaml
cp secrets/templates/mail/postfix-relay-auth.secret.example.yaml secrets/live/postfix-relay-auth.yaml
cp secrets/templates/gitlab/initial-admin-password.secret.example.yaml secrets/live/initial-admin-password.yaml
cp secrets/templates/gitlab/postgres-secret.secret.example.yaml secrets/live/postgres-secret.yaml
cp secrets/templates/gitlab/redis-secret.secret.example.yaml secrets/live/gitlab-redis.yaml
cp secrets/templates/gitlab/minio-credentials.secret.example.yaml secrets/live/minio-credentials.yaml
cp secrets/templates/gitlab/s3-credentials.secret.example.yaml secrets/live/s3-credentials.yaml
cp secrets/templates/gitlab/fake-mail-password.secret.example.yaml secrets/live/fake-mail-password.yaml
cp secrets/templates/gitlab/dev-gitlab-runner.secret.example.yaml secrets/live/dev-gitlab-runner.yaml
```

2. Edit each file in `secrets/live/` and replace every `CHANGE_ME_*` value.

3. Apply namespaces first:

```bash
./scripts/bootstrap.sh
```

4. Apply secrets + full cluster manifests:

```bash
./scripts/deploy.sh
```

## Manual Environment Reproduction

Prerequisites:

- k3s cluster reachable from `kubectl`
- cert-manager installed
- Traefik ingress controller installed
- k3s supports `helm.cattle.io/v1` `HelmChart` CRDs
- DNS records resolving to your ingress endpoint for:
  - `argocd.xulihaxlab.org`
  - `registry.xulihaxlab.org`
  - `minio.xulihaxlab.org`
  - `pg.xulihaxlab.org`

Manual apply order (without scripts):

```bash
kubectl apply -k platform/namespaces
kubectl apply -f secrets/live
kubectl apply -k .
```

## Day-2 Operations

`deploy.sh` automatically reconciles:

- Harbor external DB/Redis passwords from `postgres-auth` and `redis-auth` secrets.
- Harbor internal shared secret from `harbor-internal` (used by both core and jobservice).
- Argo CD `admin.password` from plaintext to bcrypt in `argocd-secret` (then restarts Argo CD server).

This keeps `secrets/live` developer-friendly (raw password input) while preserving required in-cluster format.

### Update cluster manifests

1. Edit manifests under `platform/` or `apps/`.
2. Validate:

```bash
kubectl kustomize . >/dev/null
```

3. Apply:

```bash
kubectl apply -k .
```

### Update secret values

1. Edit corresponding file in `secrets/live/`.
2. Re-apply:

```bash
kubectl apply -f secrets/live/<secret-file>.yaml
```

### Verify health

```bash
kubectl get pods -A
kubectl get applications.argoproj.io -n argo-cd
kubectl get ingress -A
```

## Developer Notes / Required Inputs

- You must provide all `CHANGE_ME_*` values before first deployment.
- `argocd-secret` requires a stable `server.secretkey`; generate one and keep it unchanged between deploys.
- For Argo CD login, set plaintext `admin.password` in `secrets/live/argocd-secret.yaml`; `deploy.sh` hashes it automatically.
- Postfix relay sender policy and hostname are in `apps/mail-relay-postfix/configmap.yaml`.
- Set outbound SMTP relay in `secrets/live/postfix-relay-auth.yaml` (`RELAYHOST`, optional `RELAYHOST_USERNAME`, `RELAYHOST_PASSWORD`).
- Internal SMTP endpoint for apps (for example GitLab): `smtp-relay.mail.svc.cluster.local:587`.
- GitLab Runner chart uses `dev-gitlab-runner` secret for runner token and MinIO cache credentials.
- Runner CA/certs mount for self-signed GitLab is intentionally omitted because GitLab ingress uses a valid public certificate.
- Harbor uses external PostgreSQL and Redis credentials from `harbor-core-envvars`.
- Harbor internal component auth (`core.secret` / `jobservice.secret`) comes from `harbor-internal`.
- Redis chart is configured with `auth.existingSecret=redis-auth`.
- MinIO chart is configured with `existingSecret=minio-root-user`.
- Argo CD admin password is not hardcoded; configure it post-install if needed.

## Best-Practice Decisions Applied

- Manifests split by concern (deployment/service/ingress/rbac)
- Namespaces and labels standardized
- Health probes and resource requests/limits added where applicable
- Secret templates separated from application manifests
- Kustomize used as a single deployment interface
- Legacy files isolated to `legacy/` to avoid accidental use
