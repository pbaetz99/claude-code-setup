# Mitmachen

Danke, dass du dir dieses Setup ansiehst. Das Repo ist `~/.claude` in versionierter Form:
Konfiguration, Plugin-Liste und Installationsskripte. Es ist kein Anwendungsprogramm.

## Was hier gehört

- Verbesserungen an `README.md`, `setup/` (Installations- und Exportskripte) und `settings.json`
  (Konfiguration, Plugin-Schalter, Modellwerte).
- Hinweise auf veraltete Angaben, etwa zu Plugins, Modellen oder Claude-Code-Versionen.

## Was woanders hingehört

- **ECC-Inhalte** (`agents/`, `commands/`, `skills/`, `rules/`, `scripts/`, `hooks/`,
  `AGENTS.md`, `the-security-guide.md`, `PLUGIN_SCHEMA_NOTES.md`, `marketplace.json`,
  `plugin.json`, `mcp-configs/`) stammen aus [affaan-m/ECC](https://github.com/affaan-m/ECC).
  Änderungen daran bitte dort als Issue oder Pull Request einreichen, nicht hier.

## Regeln für Beiträge

- **Allowlist-`.gitignore`:** Alles ist ignoriert, nur ausdrücklich freigegebene Pfade werden
  versioniert. Eine neue Datei braucht eine `!`-Zeile. Prüfen mit `git add -A --dry-run`.
- **Keine Geheimnisse:** keine Tokens, Passwörter, Schlüssel, Sitzungsdaten, internen Hostnamen
  oder persönlichen Pfade. Beiträge mit solchen Angaben werden abgelehnt.
- **Commit-Betreff nennt die Wirkung**, nicht die Technik. Beispiel: „Plugins: Semgrep läuft
  wieder beim Speichern“ statt „fix hook config“.
- **Zeilenenden erhalten.** Bestehende Dateien nicht stillschweigend umwandeln.
- Dokumentation und Commit-Meldungen auf Deutsch.

## Entwicklung

```bash
bash setup/install.sh                        # macOS / Linux / WSL
powershell -ExecutionPolicy Bypass -File setup/install.ps1   # Windows
python -I setup/export-plugins.py            # nach Plugin-Änderungen
```

Vor dem Einreichen: `git add -A --dry-run` ausführen und prüfen, dass keine unerwarteten Dateien
dabei sind.

## Issues

Fehler bitte mit der Vorlage „Fehlerbericht“ melden, Wünsche mit „Funktionswunsch“. Die Angaben
zur Umgebung helfen am meisten: Betriebssystem, Claude-Code-Version und der genaue Befehl.

## Mit Claude Code arbeiten

Wer dieses Repo mit Claude Code ändert, findet die Arbeitsregeln in
[`setup/CLAUDE-REPO.md`](setup/CLAUDE-REPO.md). Die Datei liegt bewusst nicht im Wurzelverzeichnis,
weil dort eine Datei in jeder Sitzung als globale Anweisung geladen würde.
