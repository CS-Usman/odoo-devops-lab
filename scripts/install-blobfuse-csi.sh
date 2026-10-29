#!/usr/bin/env bash
# Optional: Azure Blob Fuse CSI for shared prod filestore across web pods.
# See: k8s/storage/README.md and https://learn.microsoft.com/azure/storage/blobs/azure-blob-fuse-2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

: "${KUBECONFIG:?}"

echo "[blob-csi] This lab uses scripts/sync-filestore-blob.sh by default."
echo "[blob-csi] For multi-replica shared mounts, install Blob Fuse driver per Microsoft docs"
echo "           and apply a StorageClass pointing at terraform output:"
echo "             storage_account_name + odoo_prod_filestore_container_name"
echo ""
echo "           Guide: ${REPO_DIR}/k8s/storage/README.md"
exit 0
