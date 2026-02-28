#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_FILE="${ROOT_DIR}/apps/argocd-apps/harbor/application.yaml"

if ! kubectl get secret -n psql postgres-auth >/dev/null 2>&1; then
  echo "postgres-auth secret not found in namespace psql"
  exit 1
fi

if ! kubectl get secret -n redis redis-auth >/dev/null 2>&1; then
  echo "redis-auth secret not found in namespace redis"
  exit 1
fi

if ! kubectl get secret -n harbor harbor-internal >/dev/null 2>&1; then
  echo "harbor-internal secret not found in namespace harbor"
  exit 1
fi

PG_PASS="$(kubectl get secret -n psql postgres-auth -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
REDIS_PASS="$(kubectl get secret -n redis redis-auth -o jsonpath='{.data.redis-password}' | base64 -d)"
HARBOR_INTERNAL_SECRET="$(kubectl get secret -n harbor harbor-internal -o jsonpath='{.data.INTERNAL_SECRET}' | base64 -d)"

VALUES_TEMPLATE="$(perl -0777 -ne 'if(/values:\s+\|\n(.*?)\n\s*destination:/s){print $1}' "${APP_FILE}")"
VALUES_TEMPLATE="$(printf '%s' "${VALUES_TEMPLATE}" | sed 's/^[[:space:]]\{8\}//')"
VALUES_CONTENT="$(
  printf '%s' "${VALUES_TEMPLATE}" \
    | PG_PASS="${PG_PASS}" perl -0777 -pe 's/managed-via-postgres-password/$ENV{PG_PASS}/g' \
    | REDIS_PASS="${REDIS_PASS}" perl -0777 -pe 's/managed-via-redis-password/$ENV{REDIS_PASS}/g' \
    | HARBOR_INTERNAL_SECRET="${HARBOR_INTERNAL_SECRET}" perl -0777 -pe 's/managed-via-harbor-internal-secret/$ENV{HARBOR_INTERNAL_SECRET}/g'
)"

PATCH_JSON="$(jq -nc --arg values "${VALUES_CONTENT}" '{spec:{source:{helm:{values:$values}}}}')"
kubectl patch application harbor -n argo-cd --type merge -p "${PATCH_JSON}" >/dev/null
kubectl annotate application harbor -n argo-cd argocd.argoproj.io/refresh=hard --overwrite >/dev/null

echo "Harbor application passwords reconciled from Kubernetes Secrets."
