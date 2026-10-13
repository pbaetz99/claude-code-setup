# Claude-Code-Setup

Dieses Repo **ist** `~/.claude`: die komplette Konfiguration von Claude Code für Web-Entwicklung,
Security und IT-Systemadministration. Ziel ist eine Umgebung, in der Claude **sicher**
(Security-Hooks, Scanner, Review-Agents), **schnell** (Sprachserver statt Datei-Lesen, Browser- und
Doku-Werkzeuge) und **tokensparend** (Kontext aus LSP, Context7, Memory statt Raten) arbeitet.

Stand: 13.10.2026 · Claude Code 2.1.x · Windows 11, läuft aber auch auf macOS/Linux/WSL.

## Auf einem neuen Rechner einrichten

Diesen Absatz einfach an Claude geben:

> Richte mein Claude-Code-Setup ein: Klone `https://github.com/pbaetz99/claude-code-setup`
> nach `~/.claude` und führe `setup/install.ps1` (Windows) bzw. `setup/install.sh`
> (macOS/Linux/WSL) aus. Danach `claude plugin list` zeigen und mir sagen, was fehlt.

Oder von Hand (Windows):

```powershell
git clone https://github.com/pbaetz99/claude-code-setup.git "$env:USERPROFILE\.claude-setup-tmp"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude-setup-tmp\setup\install.ps1"
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude-setup-tmp"
```

Das Skript sichert eine vorhandene Konfiguration nach `~/.claude/backups/`, macht `~/.claude`
zum Checkout, installiert Marktplätze und Plugins aus `setup/plugins.json` und die Sprachserver
für die LSP-Plugins. Anmelden (`claude`) musst du einmal selbst.

Voraussetzungen: Git, Node 18+, npm, Python 3, Claude Code CLI.

## Was drin ist

| Ordner / Datei | Inhalt |
| --- | --- |
| `settings.json` | Hooks (ECC), Plugin-Schalter, bekannte Marktplätze, Berechtigungen |
| `agents/`, `commands/`, `skills/`, `rules/`, `scripts/`, `hooks/` | **ECC 2.2.2** (Everything Claude Code, affaan-m/ECC), manuell installiert: 68 Agents, 294 Skills, 94 Commands, Regeln je Sprache (nur bei passenden Dateien aktiv), Hook-Skripte |
| `AGENTS.md`, `the-security-guide.md`, `PLUGIN_SCHEMA_NOTES.md` | ECC-Begleitdokumente |
| `mcp-configs/mcp-servers.json` | ECC-**Vorlage** für MCP-Server, nur Platzhalter, nicht aktiv |
| `setup/plugins.json` | Erzeugte Liste aller Marktplätze und Plugins mit An/Aus-Zustand |
| `setup/install.ps1`, `setup/install.sh` | Einrichtung auf einem neuen Rechner |
| `setup/export-plugins.py` | Erzeugt `setup/plugins.json` neu aus dem Ist-Zustand |

## Plugins (Nutzer-Ebene, auf jedem Rechner gleich)

**Security:** claude-security (Tiefenscan), security-guidance (Warnungen bei Edits, Diff-Review
beim Stop), semgrep (Guardian, läuft nativ auf Windows), code-review.
**Web-Entwicklung:** typescript-lsp, pyright-lsp, modern-web-guidance, frontend-design,
ui-ux-pro-max, playwright, feature-dev, context7 (aktuelle Bibliotheksdoku).
**Admin / Microsoft:** microsoft-docs.
**Arbeitsweise:** claude-code-setup, claude-md-management, claude-obsidian (Wissens-Vault;
Schreiben braucht unter Windows WSL).
**Deaktiviert, aber installiert:** code-simplifier, ponytail.

Am claude.ai-Konto hängen zusätzlich: humanizer, figma, design, engineering,
product-management, data. Die kommen mit dem Login, nicht mit diesem Repo.

Noch nicht installiert, bei Bedarf eine Zeile `claude plugin install <name>@claude-plugins-official`:
`azure` (Azure MCP, braucht `az login`), `terraform`, `crowdsec`, `serena` (semantische
Codesuche, spart Tokens in großen Repos, braucht `uv`), `chrome-devtools-mcp`, `sonarqube`.

## Model-Routing (Stand 13.10.2026)

Ziel: Kosten je erledigter Aufgabe, nicht je Anfrage. Preise je MTok Input/Output: Haiku 5.5 0,10/0,50,
Sonnet 5.5 2/10, Opus 5.5 4/20, Fable 5.1 10/50.

| Ebene | Einstellung | Wo |
| --- | --- | --- |
| Hauptsession | Standard `opusplan`: Plan-Modus auf Opus 5.5, Umsetzung auf Sonnet 5.5. Harte Arbeit und alles Sicherheitsrelevante per `/model fable`. Picker bietet Opus, Sonnet, Fable mit Kosten im Text | `settings.json` → `model`, `modelPicker` |
| Effort | `medium` als Alltag; je Modell gespeichert, Fable auf `high` | `settings.json` → `effortLevel`, `modelSettings` |
| Kontext | Auto-Compaction bei 250k Tokens statt am 1M-Fenster: jeder Turn liest sonst den ganzen Verlauf neu | `modelSettings.*.autoCompactWindow` |
| Ausfall | Fällt auf Sonnet zurück, wenn das Hauptmodell überlastet ist | `fallbackModel` |
| Subagenten | Jeder ECC-Agent trägt `model` und `effort`: 9× Haiku/low (Lesen, Suchen, Doku), 25× Sonnet/medium (Umsetzung, Build-Fixer), 29× Sonnet/high (Reviewer, TDD, Diagnose), 7× Fable/high für harte Arbeit und Sicherheitsrelevantes (planner, architect, spec-miner, security-reviewer, healthcare-reviewer, network-config-reviewer, opensource-sanitizer) | `agents/*.md` |
| Plugin-Agents ohne Modell | laufen auf Sonnet, erben nie das Hauptmodell | `env.CLAUDE_CODE_SUBAGENT_MODEL` |

Wechsel in der Sitzung: `/model opus`, `/model fable`, `/effort high`. Die Regel dazu, die Claude in jeder
Sitzung liest: `rules/ecc/common/performance.md`. `modelSettings` und `modelPicker` brauchen Claude Code
2.1.251 oder neuer; ältere Versionen ignorieren die Schlüssel stillschweigend.

## Was bewusst nicht drin ist

`.credentials.json`, `~/.claude.json` (OAuth, Projektstand, ein lokaler MCP-Server mit
Umgebungswerten), `projects/` und `sessions/` (Mitschriften), `plugins/` (Cache, wird vom
Install-Skript neu gefüllt), Logs, `backups/`, `ecc/` (Laufzeitstand). Die `.gitignore` ist eine
Allowlist, `git add -A` kann davon nichts erfassen.

## Pflege

Nach einer Plugin-Änderung:

```bash
python -I setup/export-plugins.py && git add -A && git commit -m "Plugins: <was>" && git push
```

Auf einem anderen Rechner nachziehen: `git -C ~/.claude pull` und dann noch einmal das
Install-Skript, es ist wiederholbar.

ECC aktualisieren: Anleitung in `setup/ecc-README.md` und `AGENTS.md`; nach dem Update prüfen,
dass in `settings.json` kein absoluter Pfad mehr in den Hook-Befehlen steht (am 12.10.2026 stand
dort der absolute Pfad des Quellrechners base64-kodiert in den Hook-Befehlen, das bricht auf jedem anderen Rechner).

## Lizenz

MIT. Die eigenen Dateien stammen von Philipp Baetz, die ECC-Bestandteile (`agents/`, `commands/`,
`skills/`, `rules/`, `scripts/`, `hooks/`, `AGENTS.md`, `the-security-guide.md`,
`PLUGIN_SCHEMA_NOTES.md`, `marketplace.json`, `plugin.json`, `mcp-configs/`) von Affaan Mustafa,
Everything Claude Code, https://github.com/affaan-m/ECC, Version 2.2.2. Details und Lizenztext in
[LICENSE](LICENSE).

## Mitmachen

Beiträge und Fehlerberichte sind willkommen. Die Hinweise dazu stehen in
[CONTRIBUTING.md](CONTRIBUTING.md). ECC-Inhalte bitte direkt im Upstream-Projekt melden, nicht hier.
Für Änderungen am Repo selbst gelten die Arbeitsregeln in [setup/CLAUDE-REPO.md](setup/CLAUDE-REPO.md).
Diese Datei liegt bewusst nicht im Wurzelverzeichnis, weil dort jede Sitzung sie als globale
Anweisung lädt.
