#!/bin/bash
set -e

# ── Load .env if present ──
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

RUNNER_IMAGE="github-dynamic-runner"

usage() {
  echo ""
  echo "GitHub Actions Dynamic Runner Manager"
  echo ""
  echo "Usage: ./manage.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  build             Build the runner Docker image"
  echo "  start [N]         Start N ephemeral runners (default: 1)"
  echo "  stop              Stop and remove all runner containers"
  echo "  status            Show running runner containers"
  echo "  logs [container]  Tail logs of a runner container"
  echo "  cleanup           Remove all stopped runner containers"
  echo ""
  echo "Examples:"
  echo "  ./manage.sh build"
  echo "  ./manage.sh start         # Start 1 runner"
  echo "  ./manage.sh start 3       # Start 3 runners in parallel"
  echo "  ./manage.sh status"
  echo "  ./manage.sh stop"
  echo ""
}

check_env() {
  if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_REPO" ]; then
    echo "ERROR: Set GITHUB_TOKEN and GITHUB_REPO in .env file"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your values"
    exit 1
  fi
}

cmd_build() {
  echo "Building runner image..."
  docker build -t "$RUNNER_IMAGE" .
  echo "Done. Image: $RUNNER_IMAGE"
}

cmd_start() {
  check_env
  COUNT=${1:-1}
  echo "Starting $COUNT ephemeral runner(s)..."

  for i in $(seq 1 "$COUNT"); do
    CONTAINER_NAME="gh-runner-$(date +%s)-${i}"
    echo "  Starting: $CONTAINER_NAME"
    docker run -d \
      --name "$CONTAINER_NAME" \
      -e GITHUB_TOKEN="$GITHUB_TOKEN" \
      -e GITHUB_REPO="$GITHUB_REPO" \
      -e RUNNER_NAME="$CONTAINER_NAME" \
      -e RUNNER_LABELS="self-hosted,linux,docker,dynamic" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      "$RUNNER_IMAGE"
  done

  echo ""
  echo "$COUNT runner(s) started. They will auto-exit after completing one job."
  echo "Run './manage.sh status' to see them."
}

cmd_stop() {
  echo "Stopping all runner containers..."
  CONTAINERS=$(docker ps -a --filter "ancestor=$RUNNER_IMAGE" -q)
  if [ -n "$CONTAINERS" ]; then
    docker stop $CONTAINERS 2>/dev/null || true
    docker rm $CONTAINERS 2>/dev/null || true
    echo "Done."
  else
    echo "No runner containers found."
  fi
}

cmd_status() {
  echo ""
  echo "Running GitHub Actions runners:"
  echo "────────────────────────────────────────────────────────────"
  docker ps --filter "ancestor=$RUNNER_IMAGE" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
  echo ""
  echo "Stopped (completed job):"
  echo "────────────────────────────────────────────────────────────"
  docker ps -a --filter "ancestor=$RUNNER_IMAGE" --filter "status=exited" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
}

cmd_logs() {
  CONTAINER=${1:-$(docker ps --filter "ancestor=$RUNNER_IMAGE" -q | head -1)}
  if [ -z "$CONTAINER" ]; then
    echo "No runner containers running."
    exit 1
  fi
  docker logs -f "$CONTAINER"
}

cmd_cleanup() {
  echo "Removing stopped runner containers..."
  CONTAINERS=$(docker ps -a --filter "ancestor=$RUNNER_IMAGE" --filter "status=exited" -q)
  if [ -n "$CONTAINERS" ]; then
    docker rm $CONTAINERS
    echo "Done."
  else
    echo "No stopped containers to clean."
  fi
}

case "${1:-}" in
  build)    cmd_build ;;
  start)    cmd_start "$2" ;;
  stop)     cmd_stop ;;
  status)   cmd_status ;;
  logs)     cmd_logs "$2" ;;
  cleanup)  cmd_cleanup ;;
  *)        usage ;;
esac
