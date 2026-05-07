# vault_helm

Wrapper Helm chart that deploys the **official [HashiCorp Vault Helm chart](https://github.com/hashicorp/vault-helm)** (`hashicorp/vault`) on a local Minikube Kubernetes cluster.

This repo mirrors the Vault settings and GitHub Actions runner configuration from [vault_k8s_deployment](https://github.com/lineirv-hue/vault_k8s_deployment), replacing the custom Kubernetes manifests and Terraform IaC with the official Helm chart.

## How it works

```
vault_helm (this repo)
└── charts/vault-0.27.0.tgz   ← official hashicorp/vault chart (downloaded by helm dependency update)

Our templates add only what the official chart does not provide for Minikube:
  templates/pv.yaml                  ← hostPath PersistentVolume (Minikube has no dynamic provisioner)
  templates/configmap-logrotate.yaml ← logrotate config for the sidecar container

Everything else (StatefulSet, Service, ConfigMap, ServiceAccount, RBAC, …)
is rendered directly by the official chart using values from values.yaml.
```

## Repository Structure

```
vault_helm/
├── .github/
│   └── workflows/
│       ├── ci.yml              # Lint, template render, dry-run on every push/PR
│       ├── deploy-vault.yml    # Deploy after CI passes on main (or manual trigger)
│       └── destroy-vault.yml  # Tear down Vault (manual trigger)
├── charts/                     # Downloaded by helm dependency update (gitignored)
├── templates/
│   ├── pv.yaml                 # hostPath PV for Minikube
│   └── configmap-logrotate.yaml # Logrotate config for the sidecar
├── scripts/
│   ├── helm-deploy.sh          # Deploy via Helm and initialize Vault
│   ├── helm-destroy.sh         # Uninstall Helm release and clean up PV
│   ├── vault-init.sh           # Initialize Vault, unseal, enable engines
│   └── setup-self-hosted-runner.sh
├── Chart.yaml                  # Declares hashicorp/vault 0.27.0 as dependency
├── values.yaml                 # All configuration — official chart values + wrapper values
└── README.md
```

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) running
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured to target Minikube
- Vault CLI (auto-installed by `vault-init.sh` if absent)

## Vault Configuration

All settings live in [values.yaml](values.yaml). The `vault:` block is forwarded directly to the official `hashicorp/vault` subchart.

| Value | Default | Description |
|---|---|---|
| `vault.server.image.tag` | `1.15.2` | Vault image version |
| `vault.server.service.type` | `NodePort` | Service type for Minikube access |
| `vault.server.service.nodePort` | `32000` | NodePort (matches `vault_k8s_deployment`) |
| `vault.server.standalone.enabled` | `true` | Single-replica file storage mode |
| `vault.global.tlsDisable` | `true` | TLS disabled for local dev |
| `vault.server.dataStorage.size` | `1Gi` | PVC size |
| `vault.server.dataStorage.storageClass` | `manual` | Binds to our hostPath PV |
| `vault.ui.enabled` | `true` | Vault UI enabled |
| `vault.injector.enabled` | `false` | Agent injector disabled |
| `persistence.hostPath` | `/tmp/vault-data` | Minikube host path for PV |
| `vaultLogrotate.rotate.size` | `50M` | Rotate logs at this size |
| `vaultLogrotate.rotate.keep` | `5` | Rotated files to keep |

## Deployment

### 1. Start Minikube

```bash
minikube start
```

### 2. Deploy Vault

```bash
./scripts/helm-deploy.sh
```

This will:
1. Add the `hashicorp` Helm repo and run `helm dependency update`
2. Clean up any existing PV/PVC conflicts
3. Run `helm upgrade --install vault .`
4. Wait for the Vault pod to become ready
5. Run `vault-init.sh` to initialize, unseal, and configure Vault engines

### 3. Access Vault

```bash
# URL
echo "http://$(minikube ip):32000"

# Or via minikube
minikube service vault --url
```

### 4. Initialize Vault manually (if needed)

```bash
VAULT_ADDR=http://$(minikube ip):32000 ./scripts/vault-init.sh
```

Defaults to enabling:
- `kv` at `vault`
- `transit` at `transit`

To customize engines:

```bash
VAULT_ENGINES="kv:vault,transit:transit,pki:pki" ./scripts/vault-init.sh
```

### 5. Tear down

```bash
./scripts/helm-destroy.sh
```

## GitHub Actions CI/CD

All workflows run on a **self-hosted macOS runner** (same machine as Minikube).

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Every push / PR | Shell linting, `helm lint`, `helm template`, dry-run install |
| `deploy-vault.yml` | CI passes on `main` or manual | Cleanup → `helm-deploy.sh` |
| `destroy-vault.yml` | Manual only | `helm-destroy.sh` |

### Set up self-hosted runner

```bash
./scripts/setup-self-hosted-runner.sh
```

Follow the prompts to enter your GitHub runner registration token from:  
`https://github.com/lineirv-hue/vault_helm/settings/actions/runners`

## Notes

- File storage backend requires `replicaCount: 1` — do not scale the StatefulSet.
- TLS is disabled for local development. Enable `global.tlsDisable: false` and configure certificates before production use.
- The Vault root token and unseal key are saved in Vault KV at `vault/root` after initialization.
- Deployment logs are written to `logs/helm-deploy-YYYYMMDD-HHMMSS.log`.
- The `charts/` directory is gitignored; run `helm dependency update` after cloning.
