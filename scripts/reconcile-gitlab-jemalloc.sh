#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="gitlab"
DEPLOYMENTS=(
  gitlab-toolbox
  gitlab-webservice-default
  gitlab-sidekiq-all-in-1-v2
  gitlab-gitlab-exporter
)

for d in "${DEPLOYMENTS[@]}"; do
  if ! kubectl get deploy -n "${NAMESPACE}" "${d}" >/dev/null 2>&1; then
    continue
  fi

  kubectl get deploy -n "${NAMESPACE}" "${d}" -o json \
    | jq '
      (.spec.template.spec.volumes //= [])
      | if ([.spec.template.spec.volumes[]?.name] | index("host-jemalloc"))
        then .
        else .spec.template.spec.volumes += [{"name":"host-jemalloc","hostPath":{"path":"/usr/lib/aarch64-linux-gnu","type":"Directory"}}]
        end
      | (.spec.template.spec.containers[] |= (
          (.volumeMounts //= [])
          | if ([.volumeMounts[]?.name] | index("host-jemalloc"))
            then .
            else .volumeMounts += [{"name":"host-jemalloc","mountPath":"/opt/hostlib/libjemalloc.so.2","subPath":"libjemalloc.so.2","readOnly":true}]
            end
        ))
      | (.spec.template.spec.initContainers[]? |= (
          (.volumeMounts //= [])
          | if ([.volumeMounts[]?.name] | index("host-jemalloc"))
            then .
            else .volumeMounts += [{"name":"host-jemalloc","mountPath":"/opt/hostlib/libjemalloc.so.2","subPath":"libjemalloc.so.2","readOnly":true}]
            end
        ))
    ' \
    | kubectl apply -f - >/dev/null
done

echo "GitLab jemalloc host-library reconcile completed."
