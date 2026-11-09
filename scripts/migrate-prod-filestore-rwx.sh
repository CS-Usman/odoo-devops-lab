#!/usr/bin/env bash
# One-time: copy prod filestore from RWO disk PVC → Azure File (RWX) for multi-replica Odoo.
#
#   ./scripts/migrate-prod-filestore-rwx.sh
#
# Requires: kubectl, odoo-prod scaled to 0, .env not required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NS="$(odoo_namespace)"
OLD_PVC="${OLD_PVC:-odoo-prod-filestore}"
NEW_PVC="${NEW_PVC:-odoo-prod-filestore-rwx}"
SC="${FILE_STORAGE_CLASS:-azurefile-csi}"

: "${KUBECONFIG:?}"

if kubectl -n "$NS" get pvc "$NEW_PVC" >/dev/null 2>&1; then
  echo "[rwx] PVC ${NEW_PVC} already exists — skip create."
else
  echo "[rwx] Create RWX PVC ${NEW_PVC} (storageClass=${SC})..."
  kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NEW_PVC}
  namespace: ${NS}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${SC}
  resources:
    requests:
      storage: 32Gi
EOF
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Bound "pvc/${NEW_PVC}" --timeout=300s
fi

RUNNING="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=odoo-prod,app.kubernetes.io/component=web \
  --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)"
if [[ "$RUNNING" -gt 0 ]]; then
  echo "[rwx] Scale odoo-prod-web to 0 first:" >&2
  echo "  kubectl -n ${NS} scale deployment/odoo-prod-web --replicas=0" >&2
  exit 1
fi

echo "[rwx] Copy ${OLD_PVC} → ${NEW_PVC}..."
kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: filestore-rwx-migrate
  namespace: ${NS}
spec:
  restartPolicy: Never
  containers:
    - name: rsync
      image: alpine:3.20
      command: ["/bin/sh", "-c", "apk add --no-cache rsync >/dev/null && rsync -a /old/ /new/ && echo done"]
      volumeMounts:
        - name: old
          mountPath: /old
          readOnly: true
        - name: new
          mountPath: /new
  volumes:
    - name: old
      persistentVolumeClaim:
        claimName: ${OLD_PVC}
    - name: new
      persistentVolumeClaim:
        claimName: ${NEW_PVC}
EOF

kubectl -n "$NS" wait --for=condition=Ready pod/filestore-rwx-migrate --timeout=120s 2>/dev/null || true
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/filestore-rwx-migrate --timeout=600s
kubectl -n "$NS" logs pod/filestore-rwx-migrate
kubectl -n "$NS" delete pod filestore-rwx-migrate --ignore-not-found

echo "[rwx] Done. Set Helm:"
echo "  persistence.existingClaim: ${NEW_PVC}"
echo "  persistence.accessMode: ReadWriteMany"
echo "  persistence.storageClass: ${SC}"
echo "  web.replicas: 2"
echo "  Then sync Argo / helm upgrade odoo-prod."
