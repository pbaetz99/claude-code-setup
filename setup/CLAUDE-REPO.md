# Arbeitsregeln für dieses Repo (claude-code-setup)

Dieses Repo ist `~/.claude`: Konfiguration von Claude Code, ausgecheckt auf jedem Rechner.
Diese Datei gilt für Änderungen **am Repo selbst**. Sie liegt bewusst nicht als `CLAUDE.md`
im Wurzelverzeichnis, weil dort eine Datei in jeder Sitzung als globale Anweisung geladen würde.

## Befehle

```bash
bash setup/install.sh          # macOS / Linux / WSL: Einrichtung auf neuem Rechner
powershell -ExecutionPolicy Bypass -File setup/install.ps1   # Windows nativ
python -I setup/export-plugins.py   # setup/plugins.json aus dem Ist-Zustand neu erzeugen
```

## Struktur

- **Eigene Dateien:** `README.md`, `CONTRIBUTING.md`, `LICENSE`, `settings.json`, `.gitignore`,
  `setup/` (Installation, Export, `plugins.json`, `ecc-README.md`), `.github/`.
- **ECC-Inhalte** (Affaan Mustafa, MIT, Version 2.2.2): `agents/`, `commands/`, `skills/`,
  `rules/`, `scripts/`, `hooks/`, `mcp-configs/`, `AGENTS.md`, `the-security-guide.md`,
  `PLUGIN_SCHEMA_NOTES.md`, `marketplace.json`, `plugin.json`.

## Regeln für Änderungen

- **ECC-Dateien nicht ändern**, außer um Geheimnisse oder Pfade zu entfernen. Fehler in ECC
  gehen upstream an https://github.com/affaan-m/ECC.
- **`.gitignore` ist eine Allowlist.** Neue versionierte Dateien brauchen eine `!`-Zeile.
  Prüfen mit `git add -A --dry-run`. Niemals `git add -f`.
- **Nach jeder Plugin-Änderung** `python -I setup/export-plugins.py` ausführen, sonst
  stimmt `setup/plugins.json` nicht mehr.
- **`settings.json`-Hooks nicht umschreiben.** Nur Schalter und Modellwerte ändern, und die
  Änderung in der Commit-Meldung nennen.
- **Keine Zugangsdaten, Pfade oder internen Hostnamen** in Dateien, die versioniert werden.
- **Zeilenenden erhalten.** Bestehende Dateien nicht stillschweigend umwandeln.
- **Commit-Betreff nennt die Wirkung**, nicht die Technik. Beispiel: „Plugins: Semgrep ist
  wieder aktiv“.

## Sprache

Dokumentation und Commit-Meldungen auf Deutsch.
