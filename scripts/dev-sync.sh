#!/usr/bin/env bash
# Copia el plugin al directorio de plugins de Omarchy (sin symlinks) y reinicia el shell.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
id="io.github.jeanpidev.omapose"
dest="$HOME/.config/omarchy/plugins/$id"
mkdir -p "$dest"
rsync -a --delete \
  --exclude .git --exclude .claude --exclude .specify --exclude specs \
  --exclude tests --exclude scripts --exclude examples --exclude .gitignore \
  "$repo/" "$dest/"
omarchy plugin validate "$dest"
if [[ "${1:-}" != "--no-restart" ]]; then
  omarchy restart shell >/dev/null 2>&1 || true
fi
echo "Synced $id -> $dest"
