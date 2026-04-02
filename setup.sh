#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Creating external proxy_net network (if not exists)..."
if ! docker network inspect proxy_net &>/dev/null; then
  docker network create proxy_net
  echo "    Created proxy_net"
else
  echo "    proxy_net already exists, skipping"
fi

echo "==> Starting all stacks..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" up -d

echo ""
echo "All stacks are up."
