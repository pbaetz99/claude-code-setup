#!/usr/bin/env bash
# Hält dieses Setup aktuell: zieht die Konfiguration (~/.claude) vom Repo nach und
# aktualisiert die Marktplätze. Läuft als asynchroner SessionStart-Hook, blockiert nie,
# höchstens einmal pro Tag, und fasst lokale Änderungen nicht an.
# Die Claude-Code-CLI selbst aktualisiert sich über ihren eigenen Schalter (autoUpdates),
# nicht hier.
set -uo pipefail
ZIEL="$HOME/.claude"
LOG="$ZIEL/self-update.log"            # *.log ist gitignored
STAMP="$ZIEL/.last-self-update"         # ebenso ignoriert
INTERVALL=${CLAUDE_SETUP_UPDATE_INTERVAL:-86400}   # Sekunden; 0 = jedes Mal

log(){ printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null; }

# Abschalten per Umgebungsvariable
[ "${CLAUDE_SETUP_AUTO_UPDATE:-1}" = "0" ] && exit 0

# Drosselung: nur einmal je Intervall
if [ "$INTERVALL" -gt 0 ] && [ -f "$STAMP" ]; then
  letzter=$(cat "$STAMP" 2>/dev/null || echo 0)
  jetzt=$(date +%s)
  [ $((jetzt - letzter)) -lt "$INTERVALL" ] && exit 0
fi
date +%s > "$STAMP" 2>/dev/null

command -v git >/dev/null || { log "git fehlt, übersprungen"; exit 0; }
[ -d "$ZIEL/.git" ] || { log "kein Git-Checkout, übersprungen"; exit 0; }

# Nur fortfahren, wenn origin wirklich das Setup-Repo ist
remote=$(git -C "$ZIEL" remote get-url origin 2>/dev/null || echo "")
case "$remote" in
  *claude-code-setup*|*claude-setup*) : ;;
  *) log "fremdes origin ($remote), übersprungen"; exit 0 ;;
esac

# Lokale, nicht committete Änderungen: nie überschreiben
if [ -n "$(git -C "$ZIEL" status --porcelain 2>/dev/null)" ]; then
  log "lokale Änderungen vorhanden, Pull übersprungen"
else
  vorher=$(git -C "$ZIEL" rev-parse --short HEAD 2>/dev/null)
  if git -C "$ZIEL" pull --ff-only -q 2>>"$LOG"; then
    nachher=$(git -C "$ZIEL" rev-parse --short HEAD 2>/dev/null)
    [ "$vorher" != "$nachher" ] && log "Konfiguration aktualisiert: $vorher -> $nachher" || true
  else
    log "Pull nicht möglich (kein Fast-Forward oder offline), Stand bleibt"
  fi
fi

# Marktplätze im Hintergrund auffrischen (Plugins zieht Claude Code selbst nach)
command -v claude >/dev/null && claude plugin marketplace update >/dev/null 2>&1 || true
exit 0
