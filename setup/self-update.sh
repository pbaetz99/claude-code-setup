#!/usr/bin/env bash
# Hält dieses Setup aktuell. Läuft als asynchroner SessionStart-Hook, blockiert nie,
# höchstens einmal pro Tag, und fasst lokale Änderungen nicht an.
#
# Sicherheit: Das Repo enthält ausführbare Hooks. Automatisch gepullter Code wird also
# ausgeführt. Deshalb drei Stufen über CLAUDE_SETUP_UPDATE_MODE:
#   fetch   - nur holen und melden, NICHTS ausführen (sicherste Stufe)
#   verify  - nur anwenden, wenn der Commit gültig signiert ist (git --verify-signatures)
#   apply   - anwenden ohne Signaturprüfung (Standard, bequem; Vertrauen = GitHub-Zugang)
# origin muss exakt das Setup-Repo sein, kein Teilstring-Treffer.
# Die Claude-Code-CLI aktualisiert sich über ihren eigenen Schalter, nicht hier.
set -uo pipefail
ZIEL="$HOME/.claude"
LOG="$ZIEL/self-update.log"
STAMP="$ZIEL/.last-self-update"
INTERVALL=${CLAUDE_SETUP_UPDATE_INTERVAL:-86400}
MODUS=${CLAUDE_SETUP_UPDATE_MODE:-apply}
OK_HTTPS="https://github.com/pbaetz99/claude-code-setup.git"
OK_SSH="git@github.com:pbaetz99/claude-code-setup.git"

log(){ printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null; }

[ "${CLAUDE_SETUP_AUTO_UPDATE:-1}" = "0" ] && exit 0

if [ "$INTERVALL" -gt 0 ] && [ -f "$STAMP" ]; then
  letzter=$(cat "$STAMP" 2>/dev/null || echo 0); jetzt=$(date +%s)
  [ $((jetzt - letzter)) -lt "$INTERVALL" ] && exit 0
fi
date +%s > "$STAMP" 2>/dev/null

command -v git >/dev/null || { log "git fehlt, übersprungen"; exit 0; }
[ -d "$ZIEL/.git" ] || { log "kein Git-Checkout, übersprungen"; exit 0; }

# origin muss EXAKT das Setup-Repo sein (kein Teilstring)
remote=$(git -C "$ZIEL" remote get-url origin 2>/dev/null || echo "")
if [ "$remote" != "$OK_HTTPS" ] && [ "$remote" != "$OK_SSH" ]; then
  log "origin ist nicht das Setup-Repo ($remote), übersprungen"; exit 0
fi

# Lokale, nicht committete Änderungen: nie überschreiben
if [ -n "$(git -C "$ZIEL" status --porcelain 2>/dev/null)" ]; then
  log "lokale Änderungen vorhanden, übersprungen"; exit 0
fi

git -C "$ZIEL" fetch -q origin 2>>"$LOG" || { log "fetch fehlgeschlagen (offline?), Stand bleibt"; exit 0; }
lokal=$(git -C "$ZIEL" rev-parse -q HEAD 2>/dev/null)
fern=$(git -C "$ZIEL" rev-parse -q '@{u}' 2>/dev/null)
[ "$lokal" = "$fern" ] && exit 0   # schon aktuell

case "$MODUS" in
  fetch)
    log "Update verfügbar (${lokal:0:7} -> ${fern:0:7}). Modus fetch: prüfen und selbst mergen: git -C ~/.claude pull --ff-only"
    ;;
  verify)
    # Signer muss gepinnt sein, sonst zählt jede gültige Fremdsignatur. Ohne hinterlegten
    # erlaubten Schlüssel wird NICHTS angewandt.
    signers=$(git -C "$ZIEL" config --get gpg.ssh.allowedSignersFile 2>/dev/null || echo "")
    if [ -z "$signers" ] || [ ! -s "$signers" ]; then
      log "Modus verify: kein erlaubter Signer gepinnt (gpg.ssh.allowedSignersFile), NICHT angewandt."
    else
      alle_ok=1
      for c in $(git -C "$ZIEL" rev-list "$lokal..$fern" 2>/dev/null); do
        git -C "$ZIEL" verify-commit "$c" >/dev/null 2>&1 || { alle_ok=0; log "Commit $c ohne gültige Signatur des erlaubten Signers, abgebrochen."; break; }
      done
      if [ "$alle_ok" = "1" ] && git -C "$ZIEL" merge --ff-only -q '@{u}' 2>>"$LOG"; then
        log "Alle Commits signiert und angewandt: ${lokal:0:7} -> ${fern:0:7}"
      fi
    fi
    ;;
  *)  # apply
    if git -C "$ZIEL" merge --ff-only -q '@{u}' 2>>"$LOG"; then
      log "Konfiguration aktualisiert: ${lokal:0:7} -> ${fern:0:7}"
    else
      log "Kein Fast-Forward möglich, Stand bleibt"
    fi
    ;;
esac
# Plugins zieht Claude Code selbst nach; Marktplätze auffrischen
command -v claude >/dev/null && claude plugin marketplace update >/dev/null 2>&1 || true
exit 0
