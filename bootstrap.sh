#!/usr/bin/env bash
# Project Launcher (for REAPER) — instalador remoto.
#   curl -fsSL https://raw.githubusercontent.com/djenttleman/project-launcher-for-reaper/main/bootstrap.sh | bash
#
# Clona (o actualiza) el repo y delega en su install.sh.
set -euo pipefail

REPO_URL="https://github.com/djenttleman/project-launcher-for-reaper.git"
DIR="${PROJECT_LAUNCHER_DIR:-$HOME/.local/share/project-launcher}"

say() { printf '\033[38;5;114m▸\033[0m %s\n' "$1"; }
die() { printf '\033[38;5;203m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Project Launcher es solo para macOS."

command -v git >/dev/null 2>&1 || die "Falta git. Instalalo con: xcode-select --install"
command -v swiftc >/dev/null 2>&1 || die "Faltan las Command Line Tools de Xcode: xcode-select --install"

if [ -d "$DIR/.git" ]; then
  say "Actualizando $DIR"
  git -C "$DIR" pull --ff-only --quiet || die "No pude actualizar el repo (¿cambios locales en $DIR?)."
else
  say "Clonando en $DIR"
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 --quiet "$REPO_URL" "$DIR" || die "No pude clonar el repo."
fi

say "Instalando"
exec "$DIR/install.sh" "$@"
