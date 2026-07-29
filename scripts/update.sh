#!/usr/bin/env bash
#
# bookshelf-in-a-box — update script
#
# Pulls the latest Calibre-Web Automated image and recreates the container.
# Your data (library, config, ingest) lives in ./data and is NOT touched.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Pick the right compose command.
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  die "Docker Compose not found. Install Docker, then run ./setup.sh."
fi

[ -f docker-compose.yml ] || die "docker-compose.yml not found. Run this from the project folder."

if ! docker info >/dev/null 2>&1; then
  die "Docker daemon is not running. Start Docker and try again."
fi

echo "==> Pulling the latest image…"
$COMPOSE pull

echo "==> Recreating the container with the new image (data is preserved)…"
$COMPOSE up -d

echo "==> Cleaning up the old, now-unused image…"
# Only removes dangling images; never touches named/tagged images in use.
docker image prune -f >/dev/null 2>&1 || true

echo "✓ Update complete. Your library is running the latest version."
echo "  Tip: check it loaded correctly with  ${COMPOSE} logs -f"
