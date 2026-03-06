#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_ENV_FILE="$SCRIPT_DIR/.env.local"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.local.yml"

if [ -f "$DOCKER_ENV_FILE" ]; then
  docker compose --env-file "$DOCKER_ENV_FILE" -f "$COMPOSE_FILE" down "$@"
else
  docker compose -f "$COMPOSE_FILE" down "$@"
fi
