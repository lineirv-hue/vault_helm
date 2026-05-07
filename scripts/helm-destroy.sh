#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo_root/logs"
LOG_FILE=${LOG_FILE:-"$repo_root/logs/helm-destroy-$(date +%Y%m%d-%H%M%S).log"}
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Helm destroy log: $LOG_FILE"

if ! command -v helm >/dev/null 2>&1; then
  echo "Helm is required to destroy the Vault deployment."
  echo "Install it from https://helm.sh/docs/intro/install/"
  exit 1
fi

RELEASE_NAME=${RELEASE_NAME:-vault}
NAMESPACE=${NAMESPACE:-default}

echo "Uninstalling Helm release '$RELEASE_NAME' from namespace '$NAMESPACE'..."
helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" || true

echo "Cleaning up PV/PVC not managed by Helm..."
kubectl delete pvc vault-data-pvc --ignore-not-found -n "$NAMESPACE" || true
kubectl patch pv vault-data-pv -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete pv vault-data-pv --ignore-not-found || true

echo "Vault infrastructure destroyed."
