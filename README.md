# Claude-Code-Setup

Dieses Repo **ist** `~/.claude`: die komplette Konfiguration von Claude Code für Web-Entwicklung,
Security und IT-Systemadministration. Ziel ist eine Umgebung, in der Claude **sicher**
(Security-Hooks, Scanner, Review-Agents), **schnell** (Sprachserver statt Datei-Lesen, Browser- und
Doku-Werkzeuge) und **tokensparend** (Kontext aus LSP, Context7, Memory statt Raten) arbeitet.

Stand: 13.11.2026 · Claude Code 2.1.321 oder neuer · Windows 11, macOS, Linux (CachyOS), WSL.

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

### CachyOS (Arch) in einem Rutsch

Grund-Setup und Obsidian-Gedächtnis mit einem Skript, auf Wunsch auch lokale Modelle
(Qwen, Routing, flag-guard, FLUX.1). Es installiert die Pakete und Claude Code selbst und fragt vor dem
Anlegen des Vaults nach:

```bash
sudo pacman -S --needed git
git clone https://github.com/pbaetz99/claude-code-setup.git /tmp/ccs && bash /tmp/ccs/setup/cachyos.sh
```

`OHNE_OBSIDIAN=1` davorsetzen, um das Gedächtnis wegzulassen. Lokale Modelle kommen nur mit
`MIT_LOKAL=1` dazu (rund 55 GB Downloads, siehe
[setup/local-models/README.md](setup/local-models/README.md)). Danach neues Terminal und `claude` anmelden.

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
**Web-Entwicklung:** typescript-lsp, pyright-lsp, modern-web-guidance, playwright,
feature-dev, context7 (aktuelle Bibliotheksdoku).
**Admin / Microsoft:** microsoft-docs.
**Arbeitsweise:** claude-code-setup, claude-md-management, claude-obsidian (Wissens-Vault;
Schreiben braucht unter Windows WSL), ponytail (kleinste Lösung, die reicht).
**Deaktiviert, aber installiert:** code-simplifier, frontend-design, ui-ux-pro-max. Die beiden Design-Plugins
doppeln die ECC-Skills zu Frontend und Design.

Am claude.ai-Konto hängen zusätzlich: humanizer, figma, design, engineering,
product-management, data. Die kommen mit dem Login, nicht mit diesem Repo.
`settings.json` schaltet sie über `enabledPlugins` (`<name>@synced`) ab, weil die ECC-Skills reichen und ihre
53 Skills sonst das Skill-Listing füllen. Wieder einschalten: den Eintrag auf `true` setzen.

Noch nicht installiert, bei Bedarf eine Zeile `claude plugin install <name>@claude-plugins-official`:
`azure` (Azure MCP, braucht `az login`), `terraform`, `crowdsec`, `serena` (semantische
Codesuche, spart Tokens in großen Repos, braucht `uv`), `chrome-devtools-mcp`, `sonarqube`.

## Model-Routing (Stand 13.11.2026)

Ziel: Kosten je erledigter Aufgabe, nicht je Anfrage. Preise je MTok Input/Output: Haiku 5.5 0,10/0,50
(Prompts über 100k Tokens: 0,50/2,50), Sonnet 5.5 2/10, Opus 5.5 4/20, Fable 5.2 8/40.

| Ebene | Einstellung | Wo |
| --- | --- | --- |
| Hauptsession | Standard `opusplan`: Plan-Modus auf Opus 5.5, Umsetzung auf Sonnet 5.5. Harte Arbeit und alles Sicherheitsrelevante per `/model fable` (Fable 5.2). Der Picker ersetzt die eingebaute Liste und bietet Opus, Sonnet, Fable, Haiku mit Kosten im Text | `settings.json` → `model`, `modelPicker` |
| Effort | `medium` als Alltag; je Modell gespeichert, Fable auf `high`. Die Schlüssel sind kanonische Modell-IDs (`claude-fable-5-2`): bei jedem neuen Modell umstellen, sonst gelten Effort und Kompaktierungsgrenze stillschweigend nicht mehr | `settings.json` → `effortLevel`, `modelSettings` |
| Kontext | Auto-Compaction bei 250k Tokens statt am 1M-Fenster: jeder Turn liest sonst den ganzen Verlauf neu. Haiku bei 100k, darüber gilt dort der teurere Tarif | `modelSettings.*.autoCompactWindow` |
| Ausfall | Bei Überlast oder Serverfehler weiter auf Sonnet, sonst Opus; nicht bei Rate-Limits | `fallbackModel` |
| Geflaggte Anfragen | Stuft der Sicherheitsklassifikator eine Anfrage als Cyber- oder Biologie-Thema ein, wiederholt Claude Code sie automatisch auf einem älteren Modell. Danach mit `/status` prüfen, welches Modell läuft | `switchModelsOnFlag` |
| Subagenten | Jeder ECC-Agent trägt `model` und `effort`: 8× Haiku/low (Lesen, Suchen, Doku), 25× Sonnet/medium (Umsetzung, Build-Fixer), 28× Sonnet/high (Reviewer, TDD, Diagnose), 7× Fable/high für harte Arbeit und Sicherheitsrelevantes (planner, architect, spec-miner, security-reviewer, healthcare-reviewer, network-config-reviewer, opensource-sanitizer) | `agents/*.md` |
| Agents ohne Modell | laufen auf Sonnet statt auf dem Hauptmodell; Frontmatter und ein beim Aufruf übergebenes `model` haben Vorrang | `env.CLAUDE_CODE_SUBAGENT_MODEL` |

Wechsel in der Sitzung: `/model opus`, `/model fable`, `/effort high`. Die Regel dazu, die Claude in jeder
Sitzung liest: `rules/ecc/common/performance.md`. `modelSettings` und `modelPicker` brauchen Claude Code
2.1.251 oder neuer, `fable` zeigt ab 2.1.321 auf Fable 5.2; ältere Versionen ignorieren die Schlüssel stillschweigend.
Das ECC-Command `/plan` heißt hier `/ecc-plan`: `/plan` bleibt der eingebaute Plan-Modus, an dem `opusplan` hängt.

## Lokale Modelle (optional, standardmäßig nicht installiert)

Qwen-Coder lokal über Ollama mit automatischem Routing (`claude-code-router`): Hintergrund- und
einfache Tasks laufen lokal, Planung, Review und Security bleiben bei Claude. `/lokal <aufgabe>`
erzwingt das lokale Modell; lehnt Anthropic eine Antwort ab, läuft die Sitzung per
flag-guard 60 Minuten lokal weiter. Dazu FLUX.1 als lokaler Bild-MCP-Server. Abgestimmt auf
Ryzen 9 9900X, RTX 5070 Ti (16 GB) und 64 GB DDR5.

Nicht Teil von `install.sh`, sondern einmal auf dem Zielrechner (Linux/CachyOS):
`bash setup/local-models/setup-local-models.sh`, danach `claude-lokal` starten. Achtung: Dort
läuft auch der Claude-Pfad über die API-Abrechnung statt über das Abo; normales `claude`
bleibt beim Abo. Details, VRAM-Bedarf und Abwägungen:
[setup/local-models/README.md](setup/local-models/README.md).

## Obsidian als Gedächtnis (optional, Linux/macOS)

Ein Obsidian-Vault wird zum Langzeitgedächtnis von Claude (Plugin `claude-obsidian`):

- **Laden:** Beim Sitzungsstart lädt ein Hook den Kurzstand `wiki/hot.md` automatisch.
- **Speichern:** `/save` legt Entscheidungen, gelöste Fehler, Vorlieben und Runbooks
  als verlinkte Notizen ab. Claude bietet das am Ende passender Aufgaben an und
  speichert erst nach deinem Ja.
- **Abrufen:** Claude schaut mit `wiki-query` dort nach, bevor er nachfragt.

Einmal auf dem Zielrechner:

```bash
bash setup/obsidian-memory/setup-obsidian-memory.sh
```

Das Skript läuft so ab:

1. Es legt den Vault unter `~/Obsidian/Claude-Memory` an (anderer Ort per
   `OBSIDIAN_VAULT=...`) oder übernimmt einen vorhandenen. Es zeigt dir zuerst den
   Plan und schreibt erst nach deiner Bestätigung.
2. Es trägt `CLAUDE_OBSIDIAN_VAULT` und `CLAUDE_OBSIDIAN_SESSION_CONTEXT=1` ein, und zwar in
   `environment.d`, fish und bash.
3. Es legt die Regeln, wann Claude abruft und speichert, als `~/.claude/CLAUDE.md` ab
   (Vorlage: [setup/obsidian-memory/CLAUDE.md](setup/obsidian-memory/CLAUDE.md)). Eine
   vorhandene `CLAUDE.md` bleibt unangetastet.

Zugangsdaten, Patientendaten und interne Hosts kommen laut Regel nie in den Vault. Das
eingebaute Auto-Memory von Claude Code bleibt für kurze Arbeitsnotizen bestehen. Unter
nativem Windows verweigert das Plugin Schreibzugriffe; dort geht es nur über WSL.

## Abgeschaltete ECC-Hooks

`settings.json` schaltet drei ECC-Funktionen ab:

- GateGuard für Routinefälle: Er verweigert sonst den ersten Edit je Datei und den ersten Bash-Aufruf je
  Sitzung und kostet Extra-Turns, besonders in Subagents. Die beiden GateGuard-Einträge für Edit/Write und
  PowerShell fehlen im Hook-Block, `GATEGUARD_BASH_ROUTINE_DISABLED=1` nimmt den Routine-Bash-Fall heraus.
  Die Schranke vor destruktiven Bash-Befehlen (`rm -rf`, Force-Push) bleibt aktiv.
- `ECC_SKIP_OBSERVE=1`: Der Continuous-Learning-Observer schreibt sonst Ein- und Ausgaben jedes
  Tool-Aufrufs nach `~/.local/share/ecc-homunculus`, ohne dass sie ausgewertet werden.
- `ECC_SKIP_LLM_SUMMARY=1`: Sonst starten PreCompact und Sitzungsende verdeckt ein `claude -p` auf Haiku.

Weiter lokal mitgeschrieben werden `bash-commands.log`, `cost-tracker.log`, `metrics/` und `session-data/`
in `~/.claude`. Die Kostenwerte des cost-tracker sind zu hoch: Er rechnet Haiku mit 1/5, Opus mit 5/25 und Fable
mit 10/50. Verlässlich ist `/usage`. Die Regeln für HarmonyOS und React Native sind per `claudeMdExcludes` ausgenommen, weil ihre
Globs auf jede `.ts`-Datei passen.

## Was bewusst nicht drin ist

`.credentials.json`, `~/.claude.json` (OAuth, Projektstand, ein lokaler MCP-Server mit
Umgebungswerten), `projects/` und `sessions/` (Mitschriften), `plugins/` (Cache, wird vom
Install-Skript neu gefüllt), Logs, `backups/`, `ecc/` (Laufzeitstand). Die `.gitignore` ist eine
Allowlist, `git add -A` kann davon nichts erfassen.

## Automatische Updates

| Was | Wie | Abschalten |
| --- | --- | --- |
| Claude Code selbst | eigener Schalter `autoUpdates` in `~/.claude.json`, bei dir an | `claude config` bzw. `DISABLE_AUTOUPDATER=1` |
| Marktplätze und Plugins | Der offizielle Marktplatz aktualisiert sich selbst. Die vier Drittanbieter stehen in `settings.json` auf `autoUpdate: false`, weil Plugins Hooks mitbringen und fremder Code sonst unbeaufsichtigt nachgeladen würde. Aktualisieren mit `claude plugin update <id>` | Eintrag auf `true` |
| Diese Konfiguration | `setup/self-update.sh` als asynchroner SessionStart-Hook: holt den Stand, höchstens einmal je 24 Stunden, blockiert nie. `settings.json` setzt den Modus `fetch` | `CLAUDE_SETUP_AUTO_UPDATE=0` |

Das Intervall stellst du mit `CLAUDE_SETUP_UPDATE_INTERVAL` (Sekunden) ein.

Das Repo enthält ausführbare Hooks, automatisch gepullter Code läuft also mit. Darum hat
`self-update.sh` drei Stufen über `CLAUDE_SETUP_UPDATE_MODE`:

- `apply` (Standard des Skripts, in `settings.json` durch `fetch` ersetzt): wendet Fast-Forward-Updates ohne Signaturprüfung an. Bequem; das Vertrauen
  liegt dann allein auf deinem GitHub-Zugang. Wer den Zugang übernimmt, könnte Code auf alle
  Clients ausspielen.
- `verify`: wendet nur an, wenn der Commit gültig signiert ist (`git merge --verify-signatures`).
  Dafür Commit-Signierung einrichten und den Schlüssel auf jedem Client als vertrauenswürdig
  hinterlegen. Ein übernommener GitHub-Zugang allein reicht dann nicht. Die Signer-Datei
  (`gpg.ssh.allowedSignersFile`) darf nur vertrauenswürdige Schlüssel enthalten; mit
  `CLAUDE_SETUP_SIGNER` lässt sich zusätzlich der erwartete Signer festnageln.
- `fetch`: holt nur und schreibt „Update verfügbar“ ins Log, führt nichts aus. Du mergest selbst
  mit `git -C ~/.claude pull --ff-only`.

`origin` muss exakt `pbaetz99/claude-code-setup` sein; bei fremdem origin, lokalen Änderungen oder
fehlendem Fast-Forward passiert nichts außer einer Zeile im Log.

ECC selbst liegt als Dateien im Repo. Neue ECC-Versionen kommen also über dieses Repo, nicht über den Marktplatz.

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
