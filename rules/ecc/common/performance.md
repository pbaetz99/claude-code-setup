# Performance Optimization

## Model Selection Strategy

Stand 13.10.2026, Preise je MTok Input/Output: Haiku 5.5 0,10/0,50 · Sonnet 5.5 2/10 · Opus 5.5 4/20 ·
Fable 5.1 10/50. Verankert in `~/.claude/settings.json` (model, modelSettings, modelPicker, env) und im
Frontmatter jedes Agents (`model`, `effort`). Nicht pro Prompt raten, sondern diese Zuordnung nutzen.

**Hauptsession:** Standard ist `opusplan` (Plan-Modus auf Opus 5.5, Umsetzung auf Sonnet 5.5). `/model fable`
für harte Arbeit und alles Sicherheitsrelevante (Auth, Zugriff, Secrets, Krypto, Eingaben, PHI): Root-Cause-
Analysen, Architekturentscheidungen, lange autonome Läufe. `/model opus` für komplexe Arbeit ohne Sicherheitsbezug. Effort: `medium` ist der Alltag, `high` bei Korrektheit vor Kosten.

**Subagenten (Agent-Tool):** Jeder ECC-Agent trägt sein Modell im Frontmatter, nicht überschreiben.
- Haiku, effort low: reines Lesen, Suchen, Sortieren, Doku nachschlagen (code-explorer, docs-lookup,
  comment-analyzer, doc-updater, opensource-*).
- Sonnet, effort medium: Umsetzung, Build-Fixer, Tests, Refactoring.
- Sonnet, effort high: alle Reviewer, tdd-guide, Performance, Netzwerkdiagnose.
- Fable, effort high: harte Arbeit (planner, architect, spec-miner) und Sicherheitsrelevantes
  (security-reviewer, healthcare-reviewer, network-config-reviewer, opensource-sanitizer).
- Plugin-Agents ohne eigenes Modell laufen über `CLAUDE_CODE_SUBAGENT_MODEL` auf Sonnet, nie auf dem
  Hauptmodell (sonst erbt ein Suchagent Fable-Preise).

**Kostenregel:** Kosten je erledigter Aufgabe zählen, nicht je Anfrage. Ein billigeres Modell, das zwei
Anläufe braucht, ist teurer. Erst Effort senken, dann Modell wechseln.
## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Extended Thinking + Plan Mode

Extended thinking is enabled by default, reserving up to 31,999 tokens for internal reasoning.

Control extended thinking via:
- **Toggle**: Option+T (macOS) / Alt+T (Windows/Linux)
- **Config**: Set `alwaysThinkingEnabled` in `~/.claude/settings.json`
- **Budget cap**: `export MAX_THINKING_TOKENS=10000` (bash) or `$env:MAX_THINKING_TOKENS = "10000"` (PowerShell)
- **Verbose mode**: Ctrl+O to see thinking output

For complex tasks requiring deep reasoning:
1. Ensure extended thinking is enabled (on by default)
2. Enable **Plan Mode** for structured approach
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
