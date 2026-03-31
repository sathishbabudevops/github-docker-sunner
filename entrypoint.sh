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

# Capture full response first (not piped directly to jq)
API_RESPONSE=$(curl -sL -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token")

# Extract HTTP status code
HTTP_STATUS=$(echo "$API_RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
# Extract response body (everything except last line)
RESPONSE_BODY=$(echo "$API_RESPONSE" | sed '$d')

# Debug: show what we got
echo "  HTTP Status: ${HTTP_STATUS}"

if [ "$HTTP_STATUS" != "201" ]; then
  echo "ERROR: GitHub API returned HTTP ${HTTP_STATUS}"
  echo "Response: ${RESPONSE_BODY}"
  exit 1
fi

# Extract token from JSON response
REG_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.token // empty')

if [ -z "$REG_TOKEN" ]; then
  echo "ERROR: Could not extract token from response"
  echo "Response: ${RESPONSE_BODY}"
  exit 1
fi

echo "Registration token acquired."

# ── Cleanup function: remove runner on exit ──
cleanup() {
  echo ""
  echo "Removing runner..."
  REMOVE_TOKEN=$(curl -sL -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/remove-token" | jq -r '.token // empty')
  if [ -n "$REMOVE_TOKEN" ]; then
    ./config.sh remove --token "$REMOVE_TOKEN" 2>/dev/null || true
  fi
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
