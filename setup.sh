#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load env vars so we can reference CONFIG_ROOT
set -a
source "$SCRIPT_DIR/.env"
set +a

echo "==> Creating external proxy_net network (if not exists)..."
if ! docker network inspect proxy_net &>/dev/null; then
  docker network create proxy_net
  echo "    Created proxy_net"
else
  echo "    proxy_net already exists, skipping"
fi

echo "==> Setting up Traefik acme.json..."
mkdir -p "$CONFIG_ROOT/traefik"
if [ ! -f "$CONFIG_ROOT/traefik/acme.json" ]; then
  touch "$CONFIG_ROOT/traefik/acme.json"
  chmod 600 "$CONFIG_ROOT/traefik/acme.json"
  echo "    Created acme.json"
else
  echo "    acme.json already exists, skipping"
fi

echo "==> Setting up Home Assistant config directories..."
mkdir -p "$CONFIG_ROOT/homeassistant"
mkdir -p "$CONFIG_ROOT/postgres"
mkdir -p "$CONFIG_ROOT/zigbee2mqtt"
mkdir -p "$CONFIG_ROOT/mosquitto/data"
mkdir -p "$CONFIG_ROOT/mosquitto/log"

echo "==> Starting all stacks..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" up -d

echo ""
echo "All stacks are up."
