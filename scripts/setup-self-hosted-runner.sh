#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Self-Hosted Runner Setup for macOS
# Downloads, configures, and starts a self-hosted runner for vault_helm.

REPO_URL="https://github.com/lineirv-hue/vault_helm"
RUNNER_DIR="${HOME}/actions-runner"
RUNNER_VERSION="2.311.0"  # Update to latest from https://github.com/actions/runner/releases

echo "Setting up GitHub Actions self-hosted runner for $REPO_URL"
echo "Runner will be installed in: $RUNNER_DIR"

if [[ -d "$RUNNER_DIR" && -f "$RUNNER_DIR/.runner" ]]; then
  echo "Runner already configured in $RUNNER_DIR"
  echo "To reconfigure, remove $RUNNER_DIR and run this script again."
  exit 1
fi

echo "Downloading GitHub Actions Runner v$RUNNER_VERSION..."
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
curl -o actions-runner-osx-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-x64-${RUNNER_VERSION}.tar.gz
tar xzf ./actions-runner-osx-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-osx-x64-${RUNNER_VERSION}.tar.gz

echo "Configuring runner..."
echo "You will need a runner registration token from GitHub."
echo "Go to: $REPO_URL/settings/actions/runners"
echo "Click 'Add runner' > 'macOS' > Copy the token from the 'Configure' section."
echo ""
read -p "Enter the runner registration token: " -s TOKEN
echo ""

./config.sh --url "$REPO_URL" --token "$TOKEN" --labels "macos,self-hosted" --name "local-macos-$(hostname)"

echo "Starting runner..."
./run.sh &
RUNNER_PID=$!

echo "Runner started with PID: $RUNNER_PID"
echo "To stop: kill $RUNNER_PID"
echo "For persistent service: https://docs.github.com/en/actions/hosting-your-own-runners/configuring-the-self-hosted-runner-application-as-a-service"
