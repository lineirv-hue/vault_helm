#!/usr/bin/env bash
set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}
INIT_FILE=${INIT_FILE:-vault-init.json}
ENGINES=${VAULT_ENGINES:-kv:vault,transit:transit}
KEY_SHARES=${KEY_SHARES:-1}
KEY_THRESHOLD=${KEY_THRESHOLD:-1}
ROOT_SECRET_PATH=${ROOT_SECRET_PATH:-vault/root}

if ! command -v vault >/dev/null 2>&1; then
  echo "Vault CLI not found. Installing from HashiCorp releases..."
  VAULT_VERSION="1.15.2"
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ARCH="arm64"
  else
    ARCH="amd64"
  fi
  mkdir -p "$HOME/bin"
  curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${OS}_${ARCH}.zip" -o /tmp/vault.zip
  unzip -o /tmp/vault.zip -d "$HOME/bin"
  rm -f /tmp/vault.zip
  export PATH="$HOME/bin:$PATH"
  echo "Vault CLI installed: $(vault version)"
fi

export VAULT_ADDR

echo "Checking Vault status at $VAULT_ADDR..."
vault_status_json=$(vault status -format=json 2>/dev/null || true)
if [[ -z "$vault_status_json" ]]; then
  echo "Vault is not reachable at $VAULT_ADDR"
  exit 1
fi
initialized=$(echo "$vault_status_json" | python3 -c 'import sys, json; print(json.load(sys.stdin)["initialized"])')

if [[ "$initialized" == "False" ]]; then
  echo "Initializing Vault..."
  vault operator init -key-shares=$KEY_SHARES -key-threshold=$KEY_THRESHOLD -format=json > "$INIT_FILE"
  echo "Vault init output written to $INIT_FILE"

  ROOT_TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["root_token"])' "$INIT_FILE")
  UNSEAL_KEY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["unseal_keys_b64"][0])' "$INIT_FILE")

  echo ""
  echo "============================================"
  echo " Vault Initialized Successfully"
  echo "============================================"
  echo " Root Token  : $ROOT_TOKEN"
  echo " Recovery Key: $UNSEAL_KEY"
  echo "============================================"
  echo ""

  echo "Unsealing Vault..."
  vault operator unseal "$UNSEAL_KEY"
  vault login "$ROOT_TOKEN"
else
  echo "Vault is already initialized. Skipping initialization."
  if [[ -n "${ROOT_TOKEN:-}" ]]; then
    vault login "$ROOT_TOKEN"
  fi
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  if [[ -f "$INIT_FILE" ]]; then
    export VAULT_TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["root_token"])' "$INIT_FILE")
  else
    echo "VAULT_TOKEN is not set and $INIT_FILE is not available."
    echo "Set VAULT_TOKEN or provide $INIT_FILE to continue."
    exit 1
  fi
fi

echo "Enabling configured engines: $ENGINES"
IFS=',' read -ra mounts <<< "$ENGINES"
for mount in "${mounts[@]}"; do
  type=${mount%%:*}
  path=${mount#*:}
  echo "Enabling secrets engine '$type' at path '$path'..."
  vault secrets enable -path="$path" "$type" || true
  if [[ "$type" == "kv" ]]; then
    vault kv enable-version -version=2 "$path" || true
  fi
done

if [[ -n "${ROOT_TOKEN:-}" && -n "${UNSEAL_KEY:-}" ]]; then
  echo "Saving root token and recovery key to KV at $ROOT_SECRET_PATH..."
  vault kv put "$ROOT_SECRET_PATH" \
    root_token="$ROOT_TOKEN" \
    recovery_key="$UNSEAL_KEY" || true
else
  echo "Warning: root token or recovery key not available for storage in KV."
fi

echo "Vault initialization and engine configuration complete."
