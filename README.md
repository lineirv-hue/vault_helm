# vault_helm

Helm chart for deploying HashiCorp Vault on a local Minikube Kubernetes cluster.

## Repository Structure

```
vault_helm/
├── .github/
│   └── workflows/
│       ├── ci.yml            # Lint, template render, dry-run on every push/PR
│       ├── deploy-vault.yml  # Deploy after CI passes on main (or manual trigger)
│       └── destroy-vault.yml # Tear down Vault (manual trigger)
├── templates/
│   ├── _helpers.tpl          # Shared label/name helpers
│   ├── configmap-vault.yaml  # vault.hcl configuration
│   ├── configmap-logrotate.yaml # Logrotate config for sidecar
│   ├── pv.yaml               # hostPath PersistentVolume
│   ├── pvc.yaml              # PersistentVolumeClaim
│   ├── deployment.yaml       # Vault + logrotate sidecar Deployment
│   └── service.yaml          # NodePort Service (port 32000)
├── scripts/
│   ├── helm-deploy.sh        # Deploy via Helm and initialize Vault
│   ├── helm-destroy.sh       # Uninstall Helm release and clean up PV/PVC
│   ├── vault-init.sh         # Initialize Vault, unseal, enable engines
│   └── setup-self-hosted-runner.sh # Configure GitHub Actions self-hosted runner
├── Chart.yaml
├── values.yaml               # All configurable values (mirrors terraform.tfvars.json)
├── .gitignore
└── README.md
```

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) running
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured to target Minikube
- Vault CLI (auto-installed by `vault-init.sh` if absent)

## Vault Configuration

All settings live in [values.yaml](values.yaml) and mirror the configuration used in the Terraform-based deployment:

| Value | Default | Description |
|---|---|---|
| `image.tag` | `1.15.2` | Vault container image version |
| `service.nodePort` | `32000` | NodePort for Minikube access |
| `vault.ui` | `true` | Enable Vault UI |
| `vault.listener.tlsDisable` | `true` | Disable TLS (local dev only) |
| `vault.storage.path` | `/vault/data` | File storage path inside container |
| `vault.disableMlock` | `true` | Disable mlock |
| `vault.logLevel` | `info` | Vault log level |
| `vault.logDir` | `/vault/logs` | Log directory inside container |
| `logrotate.rotate.size` | `50M` | Rotate logs at this size |
| `logrotate.rotate.keep` | `5` | Number of rotated files to keep |
| `persistence.hostPath` | `/tmp/vault-data` | Host path for PersistentVolume |

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
- Clean up any existing PV/PVC conflicts
- Run `helm upgrade --install vault .`
- Wait for the Vault pod to be ready
- Run `vault-init.sh` to initialize, unseal, and configure Vault engines

### 3. Access Vault

```bash
minikube service vault --url
# or
echo "http://$(minikube ip):32000"
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
| `ci.yml` | Every push / PR | Shell validation, `helm lint`, `helm template`, dry-run |
| `deploy-vault.yml` | CI passes on `main` or manual | Cleanup → `helm-deploy.sh` |
| `destroy-vault.yml` | Manual only | `helm-destroy.sh` |

### Set up self-hosted runner

```bash
./scripts/setup-self-hosted-runner.sh
```

Follow the prompts to enter your GitHub runner registration token from:  
`https://github.com/lineirv-hue/vault_helm/settings/actions/runners`

## Notes

- File storage backend is used — keep `replicaCount: 1`.
- TLS is disabled for local development. Enable it before any production use.
- The root token and unseal key are saved in Vault KV at `vault/root` after initialization.
- Deployment logs are written to `logs/helm-deploy-YYYYMMDD-HHMMSS.log`.
