#!/usr/bin/env bash
set -euo pipefail

NS="argo-cd"
SECRET="argocd-secret"
DEPLOYMENT="argo-cd-argocd-server"

if ! kubectl get secret -n "${NS}" "${SECRET}" >/dev/null 2>&1; then
  echo "Argo CD secret ${NS}/${SECRET} not found; skipping admin password reconcile."
  exit 0
fi

ADMIN_PASSWORD_B64="$(kubectl get secret -n "${NS}" "${SECRET}" -o jsonpath='{.data.admin\.password}' 2>/dev/null || true)"
if [[ -z "${ADMIN_PASSWORD_B64}" ]]; then
  echo "Argo CD admin.password is not set in ${NS}/${SECRET}; skipping."
  exit 0
fi

ADMIN_PASSWORD_RAW="$(printf '%s' "${ADMIN_PASSWORD_B64}" | base64 -d 2>/dev/null || true)"
if [[ -z "${ADMIN_PASSWORD_RAW}" ]]; then
  echo "Argo CD admin.password is empty after decode; skipping."
  exit 0
fi

if [[ "${ADMIN_PASSWORD_RAW}" =~ ^\$2[aby]\$[0-9]{2}\$ ]]; then
  echo "Argo CD admin.password already bcrypt; no hash update needed."
  exit 0
fi

kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NS}" --timeout=180s >/dev/null
SERVER_POD="$(kubectl get pod -n "${NS}" -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${SERVER_POD}" ]]; then
  echo "Unable to find Argo CD server pod for bcrypt generation."
  exit 1
fi

HASHED_PASSWORD="$(kubectl exec -n "${NS}" "${SERVER_POD}" -- argocd account bcrypt --password "${ADMIN_PASSWORD_RAW}")"
NOW_UTC="$(date -u +%FT%TZ)"

kubectl patch secret -n "${NS}" "${SECRET}" --type merge \
  -p "{\"stringData\":{\"admin.password\":\"${HASHED_PASSWORD}\",\"admin.passwordMtime\":\"${NOW_UTC}\"}}" >/dev/null

# Drop optional plaintext helper key if someone used it.
kubectl patch secret -n "${NS}" "${SECRET}" --type json \
  -p='[{"op":"remove","path":"/data/admin.passwordPlaintext"}]' >/dev/null 2>&1 || true

kubectl rollout restart deployment/"${DEPLOYMENT}" -n "${NS}" >/dev/null
kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NS}" --timeout=180s >/dev/null

echo "Argo CD admin password reconciled: plaintext -> bcrypt."
