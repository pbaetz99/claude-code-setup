#!/usr/bin/env bash
# Richtet einen Obsidian-Vault als Langzeitgedaechtnis fuer Claude Code ein
# (Plugin claude-obsidian). Linux/macOS; unter nativem Windows verweigert das
# Plugin Schreibzugriffe (nur WSL).
#
# Manuell ausfuehren:
#   bash setup/obsidian-memory/setup-obsidian-memory.sh
#
# Umgebung: OBSIDIAN_VAULT (Standard ~/Obsidian/Claude-Memory)
#
# Wiederholbar: vorhandener Vault, vorhandene ~/.claude/CLAUDE.md und bereits
# eingetragene Umgebungsvariablen bleiben unangetastet.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="${OBSIDIAN_VAULT:-$HOME/Obsidian/Claude-Memory}"
PLUGIN_CACHE="$HOME/.claude/plugins/cache"
ENV_D="$HOME/.config/environment.d/claude-obsidian.conf"
FISH_CONF="$HOME/.config/fish/conf.d/claude-obsidian.fish"
BASHRC="$HOME/.bashrc"
BASH_MARKER="# claude-obsidian (setup/obsidian-memory)"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- 1. Plugin-CLI finden ------------------------------------------------------
have python3 || { warn "python3 fehlt."; exit 1; }
PLUGIN_DIR="$(ls -d "$PLUGIN_CACHE"/*/claude-obsidian/*/ 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/claude-obsidian.py" ]; then
  warn "Plugin claude-obsidian nicht gefunden. Erst setup/install.sh ausfuehren."
  exit 1
fi
CLI="$PLUGIN_DIR/scripts/claude-obsidian.py"
say "Plugin: $PLUGIN_DIR"

# --- 2. Vault anlegen oder uebernehmen (Plan pruefen, dann anwenden) ------------
run_reviewed() {
  local action="$1"
  local generated_at operation_id plan plan_hash answer
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  operation_id="$action-claude-memory"
  plan="$(python3 "$CLI" "$action" "$VAULT" --generated-at "$generated_at" --operation-id "$operation_id")"
  printf '%s\n' "$plan"
  plan_hash="$(printf '%s' "$plan" | grep -oE '[0-9a-f]{64}' | head -n 1 || true)"
  if [ -z "$plan_hash" ]; then
    warn "Kein Plan-Hash gefunden. Manuell nach docs/install-guide.md des Plugins weitermachen."
    return 1
  fi
  read -r -p "Plan oben anwenden ($action $VAULT)? [j/N] " answer
  if [ "$answer" != "j" ] && [ "$answer" != "J" ]; then
    warn "Abgebrochen, nichts geschrieben."
    return 1
  fi
  python3 "$CLI" "$action" "$VAULT" --generated-at "$generated_at" --operation-id "$operation_id" \
    --approved-plan-sha256 "$plan_hash" --apply
}

if [ -d "$VAULT/wiki" ]; then
  say "Vault existiert bereits: $VAULT"
elif [ -d "$VAULT/.obsidian" ]; then
  say "Bestehenden Obsidian-Vault uebernehmen (Notizen bleiben erhalten): $VAULT"
  run_reviewed adopt
else
  say "Neuen Vault anlegen: $VAULT"
  mkdir -p "$(dirname "$VAULT")"
  run_reviewed init
fi
python3 "$CLI" doctor --vault "$VAULT" || warn "doctor meldet Probleme - Ausgabe oben pruefen."

# --- 3. Umgebung: Vault + automatisches Laden von hot.md beim Sitzungsstart ------
say "Umgebungsvariablen eintragen"
mkdir -p "$(dirname "$ENV_D")"
cat > "$ENV_D" <<EOF
CLAUDE_OBSIDIAN_VAULT=$VAULT
CLAUDE_OBSIDIAN_SESSION_CONTEXT=1
CLAUDE_OBSIDIAN_SESSION_CONTEXT_VAULT=$VAULT
EOF

if have fish; then
  mkdir -p "$(dirname "$FISH_CONF")"
  cat > "$FISH_CONF" <<EOF
set -gx CLAUDE_OBSIDIAN_VAULT "$VAULT"
set -gx CLAUDE_OBSIDIAN_SESSION_CONTEXT 1
set -gx CLAUDE_OBSIDIAN_SESSION_CONTEXT_VAULT "$VAULT"
EOF
fi

if ! grep -qF "$BASH_MARKER" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<EOF

$BASH_MARKER
export CLAUDE_OBSIDIAN_VAULT="$VAULT"
export CLAUDE_OBSIDIAN_SESSION_CONTEXT=1
export CLAUDE_OBSIDIAN_SESSION_CONTEXT_VAULT="$VAULT"
EOF
fi

# --- 4. Globale Anweisung: wann Claude abruft und speichert ----------------------
if [ -f "$CLAUDE_MD" ]; then
  cp -f "$HERE/CLAUDE.md" "$CLAUDE_MD.obsidian-memory"
  warn "$CLAUDE_MD existiert - Vorlage liegt als $CLAUDE_MD.obsidian-memory daneben, bitte selbst einfuegen."
else
  cp -f "$HERE/CLAUDE.md" "$CLAUDE_MD"
fi

say "Fertig. Neues Terminal oeffnen (bzw. neu anmelden), dann 'claude' starten."
cat <<EOF
  - Beim Start laedt Claude $VAULT/wiki/hot.md automatisch.
  - Speichern:  /save        Abrufen: wiki-query (Claude nutzt es von selbst)
  - Vault in Obsidian oeffnen: "Ordner als Vault oeffnen" -> $VAULT
EOF
