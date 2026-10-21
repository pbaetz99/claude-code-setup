#!/usr/bin/env bash
# Richtet dieses Claude-Code-Setup auf macOS, Linux oder WSL ein.
# Windows nativ: setup/install.ps1 verwenden.
#
# Was passiert:
#   1. ~/.claude wird zum Checkout dieses Repos. Bestehende Konfigdateien werden vorher
#      nach ~/.claude/backups/vor-setup-<Zeit>/ gesichert.
#   2. Marktplätze und Plugins aus setup/plugins.json werden installiert; was auf dem
#      Quellrechner deaktiviert war, bleibt deaktiviert.
#   3. Sprachserver (TypeScript, Pyright) werden global per npm installiert.
# Was NICHT passiert: keine Zugangsdaten, keine Sitzungen, kein ~/.claude.json.
#
# Aufruf:  bash setup/install.sh [repo-url]
set -euo pipefail
REPO="${1:-https://github.com/pbaetz99/claude-code-setup.git}"
ZIEL="$HOME/.claude"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

for b in git node npm claude python3; do
  command -v "$b" >/dev/null || { echo "FEHLT: $b"; exit 1; }
done

mkdir -p "$ZIEL"
if [ ! -d "$ZIEL/.git" ]; then
  echo "== Sichere bestehende Konfiguration nach $ZIEL/backups/vor-setup-$STAMP"
  mkdir -p "$ZIEL/backups/vor-setup-$STAMP"
  for f in settings.json AGENTS.md agents commands skills rules hooks scripts mcp-configs; do
    [ -e "$ZIEL/$f" ] && cp -r "$ZIEL/$f" "$ZIEL/backups/vor-setup-$STAMP/"
  done
  git -C "$ZIEL" init -q
  git -C "$ZIEL" remote add origin "$REPO"
fi
echo "== Hole $REPO"
git -C "$ZIEL" fetch -q origin
git -C "$ZIEL" checkout -q -f -B main origin/main
echo "== Konfiguration steht in $ZIEL"

MANIFEST="$ZIEL/setup/plugins.json"
feld() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); exec(sys.argv[2])' "$MANIFEST" "$1"; }

echo "== Marktplätze"
feld 'for m in d["marketplaces"].values(): print(m.get("repo") or m.get("url") or "")' | while read -r src; do
  [ -z "$src" ] && continue
  if claude plugin marketplace add "$src" >/dev/null 2>&1; then echo "   + $src"; else echo "   (schon da oder fehlgeschlagen) $src"; fi
done

echo "== Plugins (Nutzer-Ebene)"
feld 'for p in d["plugins_user"]: print(p["id"], 1 if p["enabled"] else 0)' | while read -r pid en; do
  if claude plugin install -y "$pid" >/dev/null 2>&1; then echo "   + $pid"; else echo "   (fehlgeschlagen) $pid"; fi
  if [ "$en" = "0" ]; then claude plugin disable "$pid" >/dev/null 2>&1 && echo "     deaktiviert, wie auf dem Quellrechner"; fi
done
# Die claude-plugin-Befehle schreiben settings.json neu und streichen dabei "autoUpdate" der
# Marktplaetze. Repo-Stand zuruecksetzen; self-update.sh braucht ausserdem einen sauberen Checkout.
git -C "$ZIEL" checkout -- settings.json

echo "== Sprachserver für die LSP-Plugins (npm global)"
# shellcheck disable=SC2046
npm install -g $(feld 'print(" ".join(d["npm_global"]))') >/dev/null 2>&1 && echo "   + installiert" || echo "   (npm install fehlgeschlagen)"

echo
echo "Fertig. Noch zu tun:"
echo " - 'claude' starten und anmelden."
echo " - Projektgebundene Plugins (setup/plugins.json, plugins_projekt) im Projektordner mit"
echo "   'claude plugin install --scope project <id>' nachziehen, falls gewünscht."
echo " - claude.ai-Konto-Plugins hängen am Login, nichts zu tun."
