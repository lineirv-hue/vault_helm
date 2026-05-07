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

echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

echo "Fetching chart dependencies (official hashicorp/vault chart)..."
helm dependency update "$repo_root"

echo "Cleaning up any existing PV/PVC to avoid conflicts..."
kubectl delete pvc "data-${RELEASE_NAME}-0" --ignore-not-found --wait=false -n "$NAMESPACE" || true
kubectl patch pv vault-data-pv -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete pv vault-data-pv --ignore-not-found --wait=false || true

echo "Waiting for PVC and PV to terminate..."
until ! kubectl get pvc "data-${RELEASE_NAME}-0" -n "$NAMESPACE" 2>/dev/null | grep -q "data-${RELEASE_NAME}-0"; do
  echo "PVC still terminating..."; sleep 3
done
until ! kubectl get pv vault-data-pv 2>/dev/null | grep -q vault-data-pv; do
  kubectl patch pv vault-data-pv -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  echo "PV still terminating..."; sleep 3
done

# The official chart runs Vault as uid 100 / gid 1000. Pre-create the
# hostPath directory inside Minikube with matching ownership so Vault can
# write its data without a "permission denied" error.
if command -v minikube >/dev/null 2>&1; then
  HOSTPATH=$(grep 'hostPath' "$repo_root/values.yaml" | awk '{print $2}' | tr -d '"')
  HOSTPATH=${HOSTPATH:-/tmp/vault-data}
  echo "Pre-creating hostPath '$HOSTPATH' inside Minikube with uid 100 / gid 1000..."
  minikube ssh "sudo mkdir -p $HOSTPATH && sudo chown -R 100:1000 $HOSTPATH && sudo chmod -R 755 $HOSTPATH"
fi

echo "Installing/upgrading Vault Helm release '$RELEASE_NAME' in namespace '$NAMESPACE'..."
helm upgrade --install "$RELEASE_NAME" "$repo_root" \
  --namespace "$NAMESPACE" \
  --values "$repo_root/values.yaml" \
  --wait=false

# The official Vault chart readiness probe runs `vault status`, which exits
# non-zero when Vault is sealed. The pod will not reach Ready until after
# vault-init.sh initializes and unseals it. So we wait for the container to
# start (Initialized condition), then unseal, then confirm Ready.
echo "Waiting for Vault pod to start (container running, pre-unseal)..."
kubectl wait pod/"${RELEASE_NAME}-0" \
  --for=condition=initialized \
  --timeout=180s -n "$NAMESPACE"

# Give vault server a moment to start listening on 8200
sleep 5

if command -v minikube >/dev/null 2>&1; then
  MINIKUBE_IP=$(minikube ip)
  echo "Vault is available at: http://$MINIKUBE_IP:$NODE_PORT"
  echo "Or use: minikube service ${RELEASE_NAME} --url"
  export VAULT_ADDR=${VAULT_ADDR:-"http://$MINIKUBE_IP:$NODE_PORT"}
else
  echo "Vault NodePort is $NODE_PORT. Use your node IP to connect."
  export VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:$NODE_PORT"}
fi

echo ""
echo "Initializing Vault..."
bash "$repo_root/scripts/vault-init.sh"

echo "Waiting for Vault pod to be ready (post-unseal)..."
kubectl wait pod/"${RELEASE_NAME}-0" \
  --for=condition=ready \
  --timeout=60s -n "$NAMESPACE"

echo "Vault is ready."
