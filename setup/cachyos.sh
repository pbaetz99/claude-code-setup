#!/usr/bin/env bash
# Komplett-Einrichtung auf CachyOS (Arch) in einem Rutsch:
#   1. Systempakete (git, node, npm, python) und Claude Code
#   2. setup/install.sh: ~/.claude wird Checkout dieses Repos, Plugins, Sprachserver
#   3. setup/local-models/setup-local-models.sh: Qwen + Routing + flag-guard + Flux
#   4. setup/obsidian-memory/setup-obsidian-memory.sh: Obsidian-Vault als Gedaechtnis
#
# Aufruf auf dem frischen Rechner:
#   sudo pacman -S --needed git
#   git clone https://github.com/pbaetz99/claude-code-setup.git /tmp/ccs && bash /tmp/ccs/setup/cachyos.sh
#
# Schalter: OHNE_LOKAL=1 (Schritt 3 weglassen), OHNE_OBSIDIAN=1 (Schritt 4 weglassen).
# Wiederholbar: jeder Schritt laesst Vorhandenes stehen.
set -euo pipefail

REPO="https://github.com/pbaetz99/claude-code-setup.git"
ZIEL="$HOME/.claude"
BIN_DIR="$HOME/.local/bin"

say()  { printf '\n\033[1;32m###\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

have pacman || { warn "Kein pacman - dieses Skript ist fuer CachyOS/Arch. Sonst setup/install.sh nutzen."; exit 1; }
if [ "$(id -u)" -eq 0 ]; then
  warn "Nicht als root starten; sudo wird bei Bedarf selbst gefragt."
  exit 1
fi

# --- 1. Systempakete + Claude Code ---------------------------------------------
say "1/4 Systempakete"
sudo pacman -S --needed --noconfirm git nodejs npm python curl

if have nvidia-smi; then
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
  warn "nvidia-smi fehlt: NVIDIA-Treiber pruefen (CachyOS: 'sudo chwd -a'), sonst laufen Qwen/Flux auf der CPU."
fi

# Globale npm-Pakete (Sprachserver, ccr) ohne root nach ~/.local
export PATH="$BIN_DIR:$PATH"
if [ ! -w "$(npm prefix -g)/lib" ]; then
  npm config set prefix "$HOME/.local"
fi

# ~/.local/bin dauerhaft im PATH: fish (CachyOS-Standard) und bash
if have fish; then
  mkdir -p "$HOME/.config/fish/conf.d"
  echo 'fish_add_path -g $HOME/.local/bin' > "$HOME/.config/fish/conf.d/local-bin.fish"
fi
if ! grep -qF '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

if ! have claude; then
  say "Claude Code installieren (npm, integritaetsgeprueft)"
  npm install -g @anthropic-ai/claude-code
fi
have claude || { warn "claude nicht im PATH ($BIN_DIR). Neues Terminal oeffnen und Skript erneut starten."; exit 1; }

# --- 2. Grund-Setup: ~/.claude aus GitHub ---------------------------------------
say "2/4 Claude-Code-Setup aus $REPO"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 "$REPO" "$TMP/repo"
bash "$TMP/repo/setup/install.sh" "$REPO"

# Ab hier laufen die Skripte aus dem Checkout in ~/.claude.
# --- 3. Lokale Modelle ------------------------------------------------------------
if [ "${OHNE_LOKAL:-0}" != 1 ]; then
  say "3/4 Lokale Modelle (Qwen, Routing, flag-guard, Flux) - ~55 GB Downloads"
  bash "$ZIEL/setup/local-models/setup-local-models.sh"
fi

# --- 4. Obsidian-Gedaechtnis -------------------------------------------------------
if [ "${OHNE_OBSIDIAN:-0}" != 1 ]; then
  say "4/4 Obsidian-Vault als Gedaechtnis"
  bash "$ZIEL/setup/obsidian-memory/setup-obsidian-memory.sh" \
    || warn "Obsidian-Schritt nicht abgeschlossen - spaeter: bash ~/.claude/setup/obsidian-memory/setup-obsidian-memory.sh"
fi

say "Fertig. Jetzt:"
cat <<'EOF'
  1. Neues Terminal oeffnen (PATH und Umgebungsvariablen neu laden).
  2. 'claude' starten und anmelden (Abo).
  3. Fuer lokales Routing den API-Key ablegen, dann 'claude-lokal' starten:
       mkdir -p ~/.config/anthropic && install -m 600 /dev/stdin ~/.config/anthropic/api-key
     (Key einfuegen, Enter, Strg+D)
  4. Monitor ans Mainboard (Ryzen-iGPU), damit die 16 GB der RTX frei bleiben.
  Updates kommen danach automatisch: self-update zieht main beim Sitzungsstart (max. 1x/Tag).
EOF
