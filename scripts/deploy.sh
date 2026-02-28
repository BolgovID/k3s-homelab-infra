#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure namespaces exist before applying namespaced secrets.
kubectl apply -k "${ROOT_DIR}/platform/namespaces"

if compgen -G "${ROOT_DIR}/secrets/live/*.yaml" > /dev/null; then
  kubectl apply -f "${ROOT_DIR}/secrets/live"
else
  echo "No secret manifests found in secrets/live."
  echo "Copy templates from secrets/templates to secrets/live and set real values first."
  exit 1
fi

kubectl apply -k "${ROOT_DIR}"

# Argo CD chart can remove argocd-secret during reconcile when chart-managed secret is disabled.
# Re-apply declarative secret from secrets/live after chart/apply to ensure server.secretkey exists.
if [[ -f "${ROOT_DIR}/secrets/live/argocd-secret.yaml" ]]; then
  kubectl apply -f "${ROOT_DIR}/secrets/live/argocd-secret.yaml"
fi
"${ROOT_DIR}/scripts/reconcile-argocd-admin-password.sh"

# GitLab on ARM/16K-page hosts requires mounting a compatible jemalloc library from host.
"${ROOT_DIR}/scripts/reconcile-gitlab-jemalloc.sh"

# Harbor chart v19.6.0 requires non-empty external DB/Redis passwords in values.
# Keep git clean with placeholders and reconcile real values from cluster Secrets at deploy time.
"${ROOT_DIR}/scripts/reconcile-harbor-passwords.sh"

echo "Deployment submitted."
