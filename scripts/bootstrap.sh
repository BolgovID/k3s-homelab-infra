#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -k "${ROOT_DIR}/platform/namespaces"

echo "Namespaces applied."
echo "Next: create and apply secret manifests from secrets/templates into secrets/live."
