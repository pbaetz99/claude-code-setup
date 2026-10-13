#!/usr/bin/env bash
# Richtet lokale Modelle fuer Claude Code ein: Qwen-Coder (Routing via ccr) und
# FLUX.1 (Bild-MCP-Server). Gedacht fuer Linux (CachyOS), laeuft auch auf macOS/WSL.
#
# Manuell ausfuehren, NICHT Teil von setup/install.sh:
#   bash setup/local-models/setup-local-models.sh
#
# Idempotent: mehrfaches Ausfuehren ist unschaedlich. Bestehende Konfigdateien
# werden vor dem Ueberschreiben nach *.bak gesichert.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCR_DIR="$HOME/.claude-code-router"
CLAUDE_CMD_DIR="$HOME/.claude/commands"
FLUX_DIR="$HOME/.local/share/claude-flux"
QWEN_MODEL="${QWEN_MODEL:-qwen3-coder:30b}"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

backup_if_exists() { [ -f "$1" ] && cp -f "$1" "$1.bak" && warn "Gesichert: $1 -> $1.bak" || true; }

# --- 1. Voraussetzungen pruefen ------------------------------------------------
say "Voraussetzungen pruefen"
MISSING=0
for bin in node npm python3; do
  have "$bin" || { warn "fehlt: $bin"; MISSING=1; }
done
have ollama || warn "ollama nicht gefunden - fuer Qwen noetig (https://ollama.com). Weiter mit Flux moeglich."
have claude || warn "claude (CLI) nicht gefunden - MCP-Registrierung wird dann uebersprungen."
[ "$MISSING" = 1 ] && warn "Bitte fehlende Basis-Tools installieren und erneut starten." && exit 1

# --- 2. claude-code-router (Routing-Proxy) -------------------------------------
say "claude-code-router installieren/aktualisieren"
npm install -g @musistudio/claude-code-router

say "Router-Konfiguration nach $CCR_DIR kopieren"
mkdir -p "$CCR_DIR"
backup_if_exists "$CCR_DIR/config.json"
cp -f "$HERE/claude-code-router/config.json"      "$CCR_DIR/config.json"
cp -f "$HERE/claude-code-router/custom-router.js" "$CCR_DIR/custom-router.js"
warn "config.json: ANTHROPIC_API_KEY setzen und die MODEL-ID-*-Platzhalter mit aktuellen Anthropic-Modell-IDs fuellen."

# --- 3. Qwen-Coding-Modell ziehen ---------------------------------------------
if have ollama; then
  say "Qwen-Modell ziehen: $QWEN_MODEL (kann dauern)"
  ollama pull "$QWEN_MODEL" || warn "ollama pull fehlgeschlagen - Modellnamen pruefen (ollama.com)."
  warn "Uncensored-Variante gewuenscht? Passenden abliterated-Tag auf ollama.com suchen, ziehen und QWEN_MODEL + config.json/custom-router.js darauf umstellen."
fi

# --- 4. /lokal-Command bereitstellen ------------------------------------------
say "/lokal-Command nach $CLAUDE_CMD_DIR kopieren"
mkdir -p "$CLAUDE_CMD_DIR"
cp -f "$HERE/commands/lokal.md" "$CLAUDE_CMD_DIR/lokal.md"

# --- 5. FLUX.1 Bild-MCP-Server -------------------------------------------------
say "FLUX.1 Bild-Server einrichten (Python-venv in $FLUX_DIR)"
mkdir -p "$FLUX_DIR"
cp -f "$HERE/flux/flux-image-server.py" "$FLUX_DIR/flux-image-server.py"
cp -f "$HERE/flux/requirements.txt"     "$FLUX_DIR/requirements.txt"
python3 -m venv "$FLUX_DIR/venv"
# shellcheck disable=SC1091
"$FLUX_DIR/venv/bin/pip" install --upgrade pip >/dev/null
warn "torch passend zur CUDA-Version installieren, z. B.:"
warn "  $FLUX_DIR/venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cu124"
"$FLUX_DIR/venv/bin/pip" install -r "$FLUX_DIR/requirements.txt"

if have claude; then
  say "Flux-MCP-Server bei Claude Code registrieren"
  claude mcp remove flux >/dev/null 2>&1 || true
  claude mcp add-json flux "{\"command\":\"$FLUX_DIR/venv/bin/python\",\"args\":[\"$FLUX_DIR/flux-image-server.py\"]}" \
    || warn "MCP-Registrierung fehlgeschlagen - manuell mit 'claude mcp add-json flux ...' nachholen."
fi

# --- Fertig --------------------------------------------------------------------
say "Fertig. Naechste Schritte:"
cat <<'EOF'
  1. ~/.claude-code-router/config.json: ANTHROPIC_API_KEY + Modell-IDs eintragen.
  2. Coding mit Routing starten:   ccr code
       - Hintergrund/einfache Tasks laufen lokal (Qwen), der Rest bei Claude.
       - /lokal <aufgabe>           erzwingt das lokale Modell fuer diesen Aufruf.
       - /model ollama,qwen3-coder:30b  schaltet dauerhaft auf lokal (ccr-eigener Befehl).
  3. Bilder: in Claude Code das Tool des MCP-Servers 'flux' nutzen (generate_image).
  Hinweis: Der ccr-Anthropic-Pfad nutzt die API-Abrechnung, nicht dein Abo. Fuer reine
  Abo-Nutzung einfach weiter nativ 'claude' starten (ohne ccr); /lokal wirkt dann nicht.
EOF
