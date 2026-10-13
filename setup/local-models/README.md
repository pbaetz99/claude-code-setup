# Lokale Modelle: Qwen-Coder (Routing) + FLUX.1 (Bilder)

Dieser Ordner rüstet Claude Code um zwei lokale Fähigkeiten nach:

- **Qwen-Coder lokal** mit **automatischem Routing** über
  [`claude-code-router`](https://github.com/musistudio/claude-code-router) (`ccr`):
  Hintergrund- und einfache Tasks laufen lokal, der Rest bleibt bei Claude.
- **`/lokal`**-Command: erzwingt das lokale Modell für einen einzelnen Aufruf.
- **FLUX.1** als getrennter **Bild-MCP-Server**: lokale Bildgenerierung, kein
  Token-Verbrauch, nichts verlässt den Rechner.

Alles liegt bewusst **nur hier unter `setup/`** (dein eigener Namensraum). Die
ECC-Ordner `commands/`, `mcp-configs/`, `scripts/` bleiben unberührt. Das
Setup-Skript verteilt die Dateien beim Einrichten an ihre Wirkorte.

## Warum ein Proxy nötig ist

Claude Code spricht nativ die Anthropic-API. Das bestehende „Model-Routing" in
diesem Repo schaltet nur zwischen **Anthropic-Modellen** (Opus/Sonnet/Fable/Haiku)
um. Um Requests automatisch an ein **lokales** Modell zu leiten, braucht es einen
Proxy davor: `ccr` setzt `ANTHROPIC_BASE_URL` auf seinen lokalen Server und
entscheidet pro Request anhand von Regeln, welches Backend antwortet.

## Wichtige Abwägung (bitte vor dem Einschalten lesen)

Wenn du über `ccr code` arbeitest, läuft **auch** der Claude-Pfad durch den Proxy
und damit über die **Anthropic-API (Abrechnung je Token)** — **nicht** über dein
Claude-Abo (OAuth). Konsequenzen:

- Für den Anthropic-Pfad brauchst du einen `ANTHROPIC_API_KEY`.
- Wer das Abo weiter nutzen will, startet für normale Arbeit einfach nativ
  `claude` (ohne `ccr`). Das automatische Routing und `/lokal` wirken dann nicht —
  man benutzt `ccr code` gezielt, wenn lokal geroutet werden soll.

Sicherheit: Review-, Security- und Planungs-Pfade (`think`, `longContext`,
`webSearch`) bleiben in der Standard-Routing-Regel bei Claude. Das lokale Modell
übernimmt nur Hintergrund/einfache Tasks. So bleibt das Qualitäts- und
Sicherheitsnetz erhalten — passend zum Ziel „sicher".

## Voraussetzungen

- Linux (getestet für CachyOS), macOS oder WSL. `node`/`npm`, `python3`, `git`.
- [Ollama](https://ollama.com) für das lokale LLM.
- NVIDIA-GPU mit genug VRAM (siehe unten). `ccr` kommt aus npm.

### Modelle und VRAM (Richtwerte)

| Zweck | Modell | Grober VRAM-Bedarf |
| --- | --- | --- |
| Coding (Standard) | `qwen3-coder:30b` (MoE, 3B aktiv → schnell) | ~18–20 GB (Q4) |
| Bilder (Standard) | `FLUX.1-schnell` (4 Schritte, Apache-2.0, kein Gating) | ~12–24 GB, mit `FLUX_OFFLOAD=1` weniger |
| Bilder (Qualität) | `FLUX.1-dev` (HF-Login nötig) | mehr, langsamer |

Qwen und Flux müssen selten gleichzeitig „heiß" sein. Bei knappem VRAM
`FLUX_OFFLOAD=1` setzen (langsamer, aber sparsam).

> „Qwen 3.8 27B Uncensored" ist kein offizieller Name. Standard hier ist das
> offizielle `qwen3-coder:30b`. Für eine **uncensored/abliterated** Variante den
> passenden Tag auf ollama.com suchen, ziehen und in `config.json`,
> `custom-router.js` sowie `QWEN_MODEL` eintragen — Community-Tags ändern sich,
> daher bewusst nicht fest verdrahtet.

## Einrichten (auf dem Zielrechner)

```bash
bash setup/local-models/setup-local-models.sh
```

Das Skript: installiert `ccr`, kopiert `config.json` + `custom-router.js` nach
`~/.claude-code-router/`, zieht das Qwen-Modell, kopiert `lokal.md` nach
`~/.claude/commands/`, baut ein venv für den Flux-Server und registriert ihn via
`claude mcp add-json`. Es ist idempotent und sichert bestehende Configs nach
`*.bak`.

Danach **manuell** in `~/.claude-code-router/config.json`:

- `ANTHROPIC_API_KEY` in der Umgebung setzen,
- die `MODEL-ID-*`-Platzhalter mit aktuellen Anthropic-Modell-IDs füllen
  (gegen die aktuelle Anthropic-Doku prüfen).

## Nutzen

```bash
ccr code            # Claude Code mit Routing starten
```

- Normale Arbeit → Claude. Hintergrund/einfache Tasks → Qwen lokal (automatisch).
- `/lokal <aufgabe>` → erzwingt das lokale Modell für diesen Aufruf.
- `/model ollama,qwen3-coder:30b` → dauerhafter Wechsel auf lokal (ccr-eigener Befehl).
- Bilder: in Claude Code das Tool `generate_image` des MCP-Servers `flux` aufrufen.

## Dateien

| Datei | Zweck | Wirkort nach Setup |
| --- | --- | --- |
| `claude-code-router/config.json` | Provider + Routing-Regeln | `~/.claude-code-router/config.json` |
| `claude-code-router/custom-router.js` | erkennt `[[LOKAL]]`-Sentinel, erzwingt lokal | `~/.claude-code-router/custom-router.js` |
| `commands/lokal.md` | `/lokal`-Command (setzt das Sentinel) | `~/.claude/commands/lokal.md` |
| `flux/flux-image-server.py` | MCP-Bild-Server (diffusers/FLUX.1) | `~/.local/share/claude-flux/` + venv |
| `flux/requirements.txt` | Python-Abhängigkeiten des Bild-Servers | im venv installiert |
| `setup-local-models.sh` | verdrahtet alles | manuell ausführen |

## Deinstallieren

```bash
npm remove -g @musistudio/claude-code-router
rm -rf ~/.claude-code-router ~/.local/share/claude-flux
rm -f  ~/.claude/commands/lokal.md
claude mcp remove flux
```
