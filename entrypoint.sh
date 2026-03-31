#!/bin/bash
set -e

# ── Validate required env vars ──
if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_REPO" ]; then
  echo "ERROR: GITHUB_TOKEN and GITHUB_REPO are required"
  echo "  GITHUB_TOKEN = Personal Access Token (repo scope)"
  echo "  GITHUB_REPO  = owner/repo (e.g. sathishbabudevops/javaapp)"
  exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-docker-runner-$(hostname | tail -c 8)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,docker}"

echo "============================================"
echo "  GitHub Actions Dynamic Runner"
echo "============================================"
echo "  Repo:   ${GITHUB_REPO}"
echo "  Runner: ${RUNNER_NAME}"
echo "  Labels: ${RUNNER_LABELS}"
echo "  Mode:   Ephemeral (single job, auto-cleanup)"
echo "============================================"

# ── Get registration token from GitHub API ──
echo "Requesting registration token..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" | jq -r '.token')

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
  echo "ERROR: Failed to get registration token. Check your GITHUB_TOKEN and GITHUB_REPO."
  exit 1
fi

echo "Registration token acquired."

# ── Cleanup function: remove runner on exit ──
cleanup() {
  echo ""
  echo "Removing runner..."
  REMOVE_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/remove-token" | jq -r '.token')
  ./config.sh remove --token "$REMOVE_TOKEN" 2>/dev/null || true
  echo "Runner removed. Container will exit."
}

trap cleanup EXIT SIGTERM SIGINT

# ── Configure runner ──
./config.sh \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --ephemeral \
  --unattended \
  --replace \
  --disableupdate

# ── Start runner (ephemeral = exits after one job) ──
echo ""
echo "Runner is ready. Waiting for a job..."
./run.sh
