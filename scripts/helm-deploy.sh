#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo_root/logs"
LOG_FILE=${LOG_FILE:-"$repo_root/logs/helm-deploy-$(date +%Y%m%d-%H%M%S).log"}
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Helm deployment log: $LOG_FILE"

if ! command -v helm >/dev/null 2>&1; then
  echo "Helm is required to deploy Vault."
  echo "Install it from https://helm.sh/docs/intro/install/"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required."
  exit 1
fi

RELEASE_NAME=${RELEASE_NAME:-vault}
NAMESPACE=${NAMESPACE:-default}
NODE_PORT=${NODE_PORT:-32000}

echo "Cleaning up any existing PV/PVC to avoid conflicts..."
kubectl delete pvc vault-data-pvc --ignore-not-found --wait=false -n "$NAMESPACE" || true
kubectl patch pv vault-data-pv -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete pv vault-data-pv --ignore-not-found --wait=false || true

echo "Waiting for PVC and PV to terminate..."
until ! kubectl get pvc vault-data-pvc -n "$NAMESPACE" 2>/dev/null | grep -q vault-data-pvc; do
  echo "PVC still terminating..."; sleep 3
done
until ! kubectl get pv vault-data-pv 2>/dev/null | grep -q vault-data-pv; do
  kubectl patch pv vault-data-pv -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  echo "PV still terminating..."; sleep 3
done

echo "Installing/upgrading Vault Helm release '$RELEASE_NAME' in namespace '$NAMESPACE'..."
helm upgrade --install "$RELEASE_NAME" "$repo_root" \
  --namespace "$NAMESPACE" \
  --values "$repo_root/values.yaml" \
  --wait=false

echo "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=vault,app.kubernetes.io/instance=$RELEASE_NAME" \
  --timeout=180s -n "$NAMESPACE"

if command -v minikube >/dev/null 2>&1; then
  MINIKUBE_IP=$(minikube ip)
  echo "Vault is available at: http://$MINIKUBE_IP:$NODE_PORT"
  echo "Or use: minikube service vault --url"
else
  echo "Vault NodePort is $NODE_PORT. Use your node IP to connect."
fi

echo ""
echo "Initializing Vault..."
export VAULT_ADDR=${VAULT_ADDR:-"http://$(minikube ip 2>/dev/null || echo '127.0.0.1'):$NODE_PORT"}
bash "$repo_root/scripts/vault-init.sh"
