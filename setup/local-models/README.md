# Lokale Modelle: Qwen-Coder (Routing) + FLUX.1 (Bilder)

Dieser Ordner rüstet Claude Code um lokale Fähigkeiten nach:

- **Qwen-Coder lokal** mit **automatischem Routing** über
  [`claude-code-router`](https://github.com/musistudio/claude-code-router) (`ccr`):
  Hintergrund- und einfache Tasks laufen lokal, der Rest bleibt bei Claude.
- **`/lokal`**-Command: erzwingt das lokale Modell für den aktuellen Auftrag.
- **flag-guard**: lehnt Anthropic eine Antwort ab (`stop_reason: "refusal"`), läuft
  die Sitzung 60 Minuten lang lokal weiter.
- **FLUX.1** als getrennter **Bild-MCP-Server**: lokale Bildgenerierung, kein
  Token-Verbrauch, nichts verlässt den Rechner.

Alles liegt bewusst **nur hier unter `setup/`** (dein eigener Namensraum). Die
ECC-Ordner `commands/`, `mcp-configs/`, `scripts/` bleiben im Repo unberührt. Das
Setup-Skript verteilt die Dateien beim Einrichten an ihre Wirkorte; die Kopie
`~/.claude/commands/lokal.md` ist per `.gitignore` ausgenommen, damit
`self-update.sh` sie nicht als lokale Änderung wertet.

## Warum ein Proxy nötig ist

Claude Code spricht nativ die Anthropic-API. Das bestehende „Model-Routing" in
diesem Repo schaltet nur zwischen **Anthropic-Modellen** (Opus/Sonnet/Fable/Haiku)
um. Um Requests automatisch an ein **lokales** Modell zu leiten, braucht es einen
Proxy davor: `ccr` setzt `ANTHROPIC_BASE_URL` auf seinen lokalen Server und
entscheidet pro Request anhand von Regeln, welches Backend antwortet.

```
claude ──► ccr :3456 ──► background / /lokal ──────────────► Ollama :11434 (Qwen)
                    └──► default / think / longContext ──► flag-guard :3457 ──► api.anthropic.com
                                                                 └─ nach refusal ─► Ollama (60 min)
```

## Wichtige Abwägung (bitte vor dem Einschalten lesen)

Unter `claude-lokal` (= `ccr code`) läuft **auch** der Claude-Pfad über die
**Anthropic-API (Abrechnung je Token)**, nicht über dein Claude-Abo (OAuth).

- Den API-Key legst du in `~/.config/anthropic/api-key` ab (`chmod 600`). Der Starter
  `claude-lokal` setzt ihn **nur für diesen Prozess**. Nicht global exportieren: Claude
  Code nutzt ein gesetztes `ANTHROPIC_API_KEY` auch beim nativen `claude` und rechnet
  dann ebenfalls je Token ab.
- Normales `claude` (ohne Routing) läuft weiter über dein Abo; `/lokal` und
  flag-guard wirken dort nicht.
- Die `background`-Regel von ccr fängt **jede** Haiku-Anfrage ab: Titelerzeugung und
  die 9 ECC-Agents auf Haiku (code-explorer, docs-lookup …) laufen dann auf Qwen.

Sicherheit: Planungs-, Review- und Security-Pfade (`default`, `think`,
`longContext`, `webSearch`) bleiben bei Claude. Das lokale Modell übernimmt nur
Hintergrund/einfache Tasks, `/lokal`-Aufträge und abgelehnte Sitzungen.

### flag-guard

Kleiner Proxy ohne Abhängigkeiten (`claude-code-router/flag-guard.js`, Node ≥ 18),
läuft als systemd-User-Dienst nur auf `127.0.0.1:3457`.

- Reicht alles unverändert durch und liest im Stream nur mit, ob
  `stop_reason: "refusal"` vorkommt.
- Nach einer Ablehnung gehen alle weiteren Anfragen **dieser Sitzung** (erkannt über
  `metadata.user_id` von Claude Code) für `FLAG_GUARD_TTL_MIN` (60) Minuten an Ollama.
  Andere Sitzungen bleiben bei Claude.
- Der Anthropic-Key wird nie an Ollama weitergereicht. Logs enthalten keine Inhalte.
- Die abgelehnte Antwort selbst ist schon gestreamt; der **nächste** Request (z. B. dein
  „nochmal") läuft lokal.
- Sofort zurück zu Claude: `curl -X POST http://127.0.0.1:3457/_flag-guard/reset`.
- Logs: `journalctl --user -u flag-guard -f`. Tests:
  `node --test setup/local-models/claude-code-router/flag-guard.test.js`.

Ohne flag-guard: in `config.json` `api_base_url` des Providers `anthropic` auf
`https://api.anthropic.com/v1/messages` setzen.

## Voraussetzungen

- Linux mit NVIDIA-GPU (CUDA), abgestimmt auf CachyOS. Der NF4-Pfad von Flux braucht
  CUDA; macOS wird nicht unterstützt.
- `node`/`npm`, `python3`, `git`, [Ollama](https://ollama.com). Auf CachyOS/Arch
  installiert das Skript die Pakete selbst.
- Plattenplatz: ~19 GB (Qwen) + ~35 GB (Flux im Hugging-Face-Cache) + ~6 GB (venv).
- Hugging-Face-Konto: FLUX.1-schnell ist gated. Auf
  https://huggingface.co/black-forest-labs/FLUX.1-schnell die Lizenz akzeptieren und
  `hf auth login` ausführen (Token mit Leserecht; gilt für jede hf-Installation). Ohne
  Login bricht das Vorabladen mit 401 ab; nachholen mit
  `~/.local/share/claude-flux/venv/bin/hf auth login` und Skript erneut starten.
- ccr ist auf 1.0.73 gepinnt: 3.x übernimmt beim ersten Start die globale
  `~/.claude/settings.json` (Base-URL auf ccr) und passt nicht zu dieser Konfiguration.

### Zielhardware: Ryzen 9 9900X + RTX 5070 Ti (16 GB) + 64 GB DDR5

| Baustein | Einstellung | Warum |
| --- | --- | --- |
| Qwen (Ollama) | `qwen3-coder:30b` Q4, ~19 GB: Großteil auf der GPU, Rest im RAM | MoE mit 3B aktiven Parametern; der CPU-Anteil bremst kaum, 64 GB DDR5 und 12 Kerne fangen ihn ab |
| Ollama-Drop-in | `OLLAMA_CONTEXT_LENGTH=65536`, `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_KEEP_ALIVE=30m`, nur `127.0.0.1` | Claude Code schickt große Systemprompts; q8-KV halbiert den Kontextspeicher (~3 GB bei 64k) |
| Flux | Transformer und T5-Encoder in NF4, `enable_model_cpu_offload` | bf16-Flux bräuchte ~33 GB; NF4 bleibt offload-fähig, Spitze ~10–13 GB |
| Flux ↔ Qwen | vor jedem Bild entlädt der Flux-Server laufende Ollama-Modelle (`keep_alive: 0`) | beide zusammen passen nicht in 16 GB; Ollama lädt Qwen beim nächsten Coding-Request neu (~5–10 s) |
| PyTorch | `torch>=2.7` aus `cu128` | Blackwell (sm_120) läuft erst mit CUDA 12.8 |
| Monitor | am Mainboard (Ryzen-iGPU) anschließen | Desktop belegt sonst 0,5–1,5 GB VRAM der RTX |

Wer eine Karte mit ≥24 GB hat: `FLUX_QUANT=none` und `FLUX_OFFLOAD=0` für volle
bf16-Qualität und mehr Tempo.

### Modelle und Speicher (Richtwerte)

| Zweck | Modell | Speicher auf 16 GB |
| --- | --- | --- |
| Coding (Standard) | `qwen3-coder:30b` (MoE, 3B aktiv → schnell) | 16 GB VRAM voll + ~8 GB RAM (Q4 + q8-KV bei 64k) |
| Bilder (Standard) | `FLUX.1-schnell` (4 Schritte, Apache-2.0, HF-Login + Lizenz nötig) | ~10–13 GB VRAM Spitze, Gewichte sonst im RAM |
| Bilder (Qualität) | `FLUX.1-dev` (HF-Login nötig; Schritte 28 und Guidance 3.5 automatisch) | gleich, aber ~7× langsamer |

> „Qwen 3.8 27B Uncensored" ist kein offizieller Name. Standard hier ist das
> offizielle `qwen3-coder:30b`. Für eine **uncensored/abliterated** Variante den
> passenden Tag auf ollama.com suchen und das Skript mit `QWEN_MODEL=<tag>` erneut
> starten; es setzt den Namen in Router-Konfiguration und flag-guard ein.

## Einrichten (auf dem Zielrechner)

```bash
bash setup/local-models/setup-local-models.sh
```

Das Skript, in dieser Reihenfolge:

1. installiert auf CachyOS/Arch per `pacman` `ollama-cuda`, `nodejs`, `npm`, `python`;
2. installiert `ccr` (ohne Root-Rechte nach `~/.local`);
3. legt `config.json` (nur falls noch nicht vorhanden, sonst `config.json.new`),
   `custom-router.js` und `flag-guard.js` nach `~/.claude-code-router/` (`chmod 600`/`700`);
4. legt den Starter `~/.local/bin/claude-lokal` an;
5. richtet flag-guard als User-Dienst ein;
6. schreibt das Ollama-Drop-in und startet den Dienst;
7. zieht das Qwen-Modell;
8. kopiert `lokal.md` nach `~/.claude/commands/`;
9. baut ein venv für den Flux-Server (torch aus `cu128`), lädt das Flux-Modell vorab
   (`FLUX_WARMUP=0` überspringt das) und registriert den Server mit
   `claude mcp add --scope user` (in allen Projekten verfügbar).

Danach nur noch den API-Key ablegen:

```bash
mkdir -p ~/.config/anthropic && install -m 600 /dev/stdin ~/.config/anthropic/api-key
```

(Key einfügen, Enter, Strg+D.)

## Nutzen

```bash
claude-lokal        # Claude Code mit Routing + flag-guard starten
```

- Normale Arbeit → Claude. Hintergrund/einfache Tasks → Qwen lokal (automatisch).
- Ablehnung durch Anthropic → Sitzung 60 min lokal (flag-guard).
- `/lokal <aufgabe>` → erzwingt das lokale Modell für diesen Auftrag, auch über
  Tool-Aufrufe hinweg. Ab 60k Tokens Kontext bleibt es bei Claude, weil Ollama sonst
  den Anfang des Prompts abschneidet.
- `/model ollama,qwen3-coder:30b` → dauerhafter Wechsel auf lokal (ccr-eigener Befehl).
- Bilder: in Claude Code das Tool `generate_image` des MCP-Servers `flux` aufrufen
  (256–2048 px, Vielfaches von 16, 1–50 Schritte). Bilder landen in `~/flux-output/`.

## Dateien

| Datei | Zweck | Wirkort nach Setup |
| --- | --- | --- |
| `claude-code-router/config.json` | Provider + Routing-Regeln | `~/.claude-code-router/config.json` |
| `claude-code-router/custom-router.js` | erkennt `[[LOKAL]]`-Sentinel, erzwingt lokal | `~/.claude-code-router/custom-router.js` |
| `claude-code-router/flag-guard.js` | nach Ablehnung Sitzung lokal | `~/.claude-code-router/flag-guard.js` + User-Dienst |
| `claude-code-router/flag-guard.test.js` | Tests (`node --test`) | bleibt im Repo |
| `commands/lokal.md` | `/lokal`-Command (setzt das Sentinel) | `~/.claude/commands/lokal.md` |
| `flux/flux-image-server.py` | MCP-Bild-Server (diffusers/FLUX.1, NF4) | `~/.local/share/claude-flux/` + venv |
| `flux/requirements.txt` | Python-Abhängigkeiten des Bild-Servers | im venv installiert |
| `setup-local-models.sh` | verdrahtet alles | manuell ausführen |

## Deinstallieren

```bash
systemctl --user disable --now flag-guard && rm -f ~/.config/systemd/user/flag-guard.service
npm remove -g @musistudio/claude-code-router    # bzw. mit --prefix ~/.local
rm -rf ~/.claude-code-router ~/.local/share/claude-flux ~/.local/bin/claude-lokal
rm -f  ~/.claude/commands/lokal.md
claude mcp remove --scope user flux
ollama rm qwen3-coder:30b
rm -rf ~/.cache/huggingface/hub/models--black-forest-labs--FLUX.1-*
sudo rm -f /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

Den API-Key in `~/.config/anthropic/api-key` löschst du bei Bedarf selbst.
