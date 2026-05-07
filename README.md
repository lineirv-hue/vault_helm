# vault_helm

Helm charts for deploying HashiCorp Vault on Kubernetes.

## Overview

This repository contains Helm chart configurations and values for deploying and managing Vault in a Kubernetes cluster.

## Prerequisites

- Kubernetes cluster
- Helm 3.x
- kubectl configured to target your cluster

## Usage

```bash
# Add the HashiCorp Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault using values from this repo
helm install vault hashicorp/vault -f values.yaml
```

## Repository Structure

```
vault_helm/
├── README.md
├── .gitignore
└── values/         # Environment-specific values files
```
