#!/usr/bin/env bash
# Richtet lokale Modelle fuer Claude Code ein: Qwen-Coder (Routing via ccr + flag-guard)
# und FLUX.1 (Bild-MCP-Server). Fuer Linux mit NVIDIA-GPU (CUDA), abgestimmt auf
# CachyOS + Ryzen 9 9900X + RTX 5070 Ti (16 GB) + 64 GB RAM.
#
# Manuell ausfuehren, NICHT Teil von setup/install.sh:
#   bash setup/local-models/setup-local-models.sh
#
# Wiederholbar: eine vorhandene ~/.claude-code-router/config.json bleibt unangetastet,
# die neue Vorlage landet dann als config.json.new daneben.
#
# Umgebung: QWEN_MODEL (Standard qwen3-coder:30b), TORCH_INDEX_URL (Standard cu128),
#           FLUX_WARMUP=0 ueberspringt den Flux-Download (~35 GB) beim Setup.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCR_DIR="$HOME/.claude-code-router"
CLAUDE_CMD_DIR="$HOME/.claude/commands"
FLUX_DIR="$HOME/.local/share/claude-flux"
BIN_DIR="$HOME/.local/bin"
KEY_FILE="$HOME/.config/anthropic/api-key"
UNIT_DIR="$HOME/.config/systemd/user"
QWEN_MODEL="${QWEN_MODEL:-qwen3-coder:30b}"
DEFAULT_QWEN="qwen3-coder:30b"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"
OLLAMA_WAIT_SECONDS=30
# Gepinnt: ccr 3.x kennt kein 'ccr code'/config.json mehr und schreibt beim ersten Start
# ANTHROPIC_BASE_URL + apiKeyHelper in die globale ~/.claude/settings.json.
CCR_PKG="@musistudio/claude-code-router@1.0.73"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Vorlage nach Ziel kopieren, Modellnamen einsetzen; vorhandenes Ziel nie ueberschreiben.
install_template() {
  local src="$1" dest="$2" target="$2"
  if [ -f "$dest" ]; then
    target="$dest.new"
    warn "$dest existiert - neue Vorlage als $target (Unterschiede selbst uebernehmen)."
  fi
  sed "s|$DEFAULT_QWEN|$QWEN_MODEL|g" "$src" > "$target"
  chmod 600 "$target"
}

# --- 0. CachyOS/Arch: Pakete (ollama-cuda nutzt die RTX-Karte) ------------------
if have pacman; then
  say "Pakete per pacman installieren (sudo): ollama-cuda nodejs npm python"
  sudo pacman -S --needed --noconfirm ollama-cuda nodejs npm python \
    || warn "pacman fehlgeschlagen - Pakete bitte manuell installieren."
fi

# --- 1. Voraussetzungen pruefen ------------------------------------------------
say "Voraussetzungen pruefen"
MISSING=0
for bin in node npm python3; do
  have "$bin" || { warn "fehlt: $bin"; MISSING=1; }
done
have ollama || warn "ollama nicht gefunden - fuer Qwen noetig (https://ollama.com). Weiter mit Flux moeglich."
have claude || warn "claude (CLI) nicht gefunden - MCP-Registrierung wird dann uebersprungen."
if [ "$MISSING" = 1 ]; then
  warn "Bitte fehlende Basis-Tools installieren und erneut starten."
  exit 1
fi

# --- 2. claude-code-router (Routing-Proxy) -------------------------------------
say "claude-code-router installieren/aktualisieren"
NPM_PREFIX="$(npm config get prefix)"
if [ -w "$NPM_PREFIX/lib" ] || [ -w "$NPM_PREFIX" ]; then
  npm install -g "$CCR_PKG"
else
  # Arch: globaler Prefix /usr gehoert root -> ohne sudo ins Nutzerverzeichnis.
  npm install -g --prefix "$HOME/.local" "$CCR_PKG"
fi
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR in den PATH aufnehmen (ccr, claude-lokal)." ;; esac

say "Router-Konfiguration nach $CCR_DIR"
mkdir -p "$CCR_DIR"
chmod 700 "$CCR_DIR"
install_template "$HERE/claude-code-router/config.json" "$CCR_DIR/config.json"
cp -f "$HERE/claude-code-router/custom-router.js" "$CCR_DIR/custom-router.js"
cp -f "$HERE/claude-code-router/flag-guard.js"    "$CCR_DIR/flag-guard.js"

# Starter: setzt den API-Key nur fuer diesen Prozess. Global exportiert wuerde er auch
# das native 'claude' vom Abo auf API-Abrechnung umstellen.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude-lokal" <<'EOF'
#!/usr/bin/env bash
# Claude Code mit lokalem Routing (ccr + flag-guard). Key liegt nur in der Datei unten.
set -euo pipefail
KEY_FILE="${ANTHROPIC_KEY_FILE:-$HOME/.config/anthropic/api-key}"
if [ ! -r "$KEY_FILE" ]; then
  echo "API-Key fehlt: $KEY_FILE anlegen (eine Zeile, chmod 600)." >&2
  exit 1
fi
ANTHROPIC_API_KEY="$(tr -d '[:space:]' < "$KEY_FILE")" exec ccr code "$@"
EOF
chmod 755 "$BIN_DIR/claude-lokal"
mkdir -p "$(dirname "$KEY_FILE")"
chmod 700 "$(dirname "$KEY_FILE")"
[ -f "$KEY_FILE" ] || warn "API-Key fehlt: in $KEY_FILE ablegen und 'chmod 600' setzen."

# --- 3. flag-guard als systemd-User-Dienst ------------------------------------
if have systemctl; then
  say "flag-guard als User-Dienst einrichten (127.0.0.1:3457)"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/flag-guard.service" <<EOF
[Unit]
Description=flag-guard: nach Anthropic-Ablehnung Sitzung auf lokales Modell umleiten

[Service]
ExecStart=$(command -v node) %h/.claude-code-router/flag-guard.js
Environment=FLAG_GUARD_LOCAL_MODEL=$QWEN_MODEL
Environment=FLAG_GUARD_TTL_MIN=60
Restart=on-failure
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now flag-guard.service
  systemctl --user restart flag-guard.service
else
  warn "Kein systemd: flag-guard manuell starten: node $CCR_DIR/flag-guard.js &"
fi

# --- 4. Ollama fuer 16 GB VRAM + 64 GB RAM tunen (systemd-Drop-in) --------------
# qwen3-coder:30b (Q4, ~19 GB) passt nicht ganz in 16 GB: Ollama legt den Rest in den
# RAM. Als MoE mit 3B aktiven Parametern bleibt das schnell. q8_0-KV-Cache und Flash
# Attention halbieren den Kontext-Speicher, damit 64k Kontext (Claude-Code-Systemprompt
# ist gross) noch auf die GPU passt. Ein Modell, ein Request gleichzeitig = kein VRAM-Streit.
if have systemctl && systemctl cat ollama.service >/dev/null 2>&1 && ! sudo -v; then
  # Ohne sudo (z. B. Domaenenkonto) nicht unter set -e abbrechen, sondern Rest weiterlaufen lassen.
  warn "Kein sudo - Ollama-Tuning uebersprungen. Override-Datei unten als Admin anlegen, dann: systemctl enable --now ollama"
elif have systemctl && systemctl cat ollama.service >/dev/null 2>&1; then
  say "Ollama-Tuning nach /etc/systemd/system/ollama.service.d/override.conf (sudo)"
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_CONTEXT_LENGTH=65536"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now ollama
  sudo systemctl restart ollama
fi

# --- 5. Qwen-Coding-Modell ziehen ---------------------------------------------
if have ollama; then
  for _ in $(seq "$OLLAMA_WAIT_SECONDS"); do
    ollama list >/dev/null 2>&1 && break
    sleep 1
  done
  say "Qwen-Modell ziehen: $QWEN_MODEL (~19 GB, kann dauern)"
  ollama pull "$QWEN_MODEL" || warn "ollama pull fehlgeschlagen - Modellnamen pruefen (ollama.com)."
  if [ "$QWEN_MODEL" = "$DEFAULT_QWEN" ]; then
    warn "Uncensored-Variante gewuenscht? Abliterated-Tag auf ollama.com suchen und Skript mit QWEN_MODEL=<tag> erneut starten."
  fi
fi

# --- 6. /lokal-Command bereitstellen ------------------------------------------
say "/lokal-Command nach $CLAUDE_CMD_DIR kopieren"
mkdir -p "$CLAUDE_CMD_DIR"
cp -f "$HERE/commands/lokal.md" "$CLAUDE_CMD_DIR/lokal.md"

# --- 7. FLUX.1 Bild-MCP-Server -------------------------------------------------
say "FLUX.1 Bild-Server einrichten (Python-venv in $FLUX_DIR)"
mkdir -p "$FLUX_DIR"
cp -f "$HERE/flux/flux-image-server.py" "$FLUX_DIR/flux-image-server.py"
cp -f "$HERE/flux/requirements.txt"     "$FLUX_DIR/requirements.txt"
python3 -m venv "$FLUX_DIR/venv"
"$FLUX_DIR/venv/bin/pip" install --upgrade pip >/dev/null
# RTX 50xx (Blackwell) braucht CUDA-12.8-Wheels; Override per TORCH_INDEX_URL moeglich.
say "torch (>=2.7) aus $TORCH_INDEX_URL installieren"
"$FLUX_DIR/venv/bin/pip" install "torch>=2.7.0" --index-url "$TORCH_INDEX_URL"
"$FLUX_DIR/venv/bin/pip" install -r "$FLUX_DIR/requirements.txt"

if [ "${FLUX_WARMUP:-1}" = 1 ]; then
  say "Flux-Modell vorab laden (~35 GB HF-Cache), damit der erste Tool-Aufruf nicht haengt"
  "$FLUX_DIR/venv/bin/python" "$FLUX_DIR/flux-image-server.py" --warmup \
    || warn "Warmup fehlgeschlagen - erster generate_image-Aufruf laedt dann nach."
fi

if have claude; then
  say "Flux-MCP-Server bei Claude Code registrieren (Scope user = in allen Projekten)"
  claude mcp remove --scope user flux >/dev/null 2>&1 || true
  claude mcp add --scope user flux -- "$FLUX_DIR/venv/bin/python" "$FLUX_DIR/flux-image-server.py" \
    || warn "MCP-Registrierung fehlgeschlagen - manuell mit 'claude mcp add --scope user flux -- ...' nachholen."
fi

# --- Fertig --------------------------------------------------------------------
say "Fertig. Naechste Schritte:"
cat <<EOF
  1. Anthropic-API-Key in $KEY_FILE ablegen (chmod 600). NICHT global exportieren.
  2. Coding mit Routing starten:   claude-lokal
       - Hintergrund/einfache Tasks laufen lokal (Qwen), der Rest bei Claude.
       - Lehnt Anthropic ab (refusal), laeuft die Sitzung 60 min lokal (flag-guard).
       - /lokal <aufgabe>           erzwingt das lokale Modell fuer diesen Aufruf.
       - /model ollama,$QWEN_MODEL  schaltet dauerhaft auf lokal (ccr-eigener Befehl).
  3. Bilder: in Claude Code das Tool des MCP-Servers 'flux' nutzen (generate_image).
     Flux entlaedt vorher Qwen aus dem VRAM (16 GB reichen nicht fuer beide).
  Normales 'claude' (ohne Routing) laeuft weiter ueber dein Abo.
  Tipp: Monitor an die Ryzen-iGPU (Mainboard-Ausgang) haengen, dann gehoeren die
  16 GB der RTX 5070 Ti komplett den Modellen.
EOF
