# Performance Optimization

## Model Selection Strategy

Stand 13.11.2026, Preise je MTok Input/Output: Haiku 5.5 0,10/0,50 (Prompts über 100k Tokens: 0,50/2,50) ·
Sonnet 5.5 2/10 · Opus 5.5 4/20 · Fable 5.2 8/40. Verankert in `~/.claude/settings.json` (model, modelSettings,
modelPicker, env) und im Frontmatter jedes Agents (`model`, `effort`). Nicht pro Prompt raten, sondern diese
Zuordnung nutzen.

**Hauptsession:** Standard ist `opusplan` (Plan-Modus auf Opus, Umsetzung auf Sonnet; ohne Plan-Modus läuft
alles auf Sonnet). `/model fable` (Fable 5.2, effort high) für harte Arbeit und alles Sicherheitsrelevante
(Auth, Zugriff, Secrets, Krypto, Eingaben, PHI): Root-Cause-Analysen, Architekturentscheidungen, lange autonome
Läufe. `/model opus` für komplexe Arbeit, bei der Sonnet zwei Anläufe bräuchte. Effort: `medium` ist der
Alltag, `high` bei Korrektheit vor Kosten.

**Geflaggte Anfragen:** Stuft der Sicherheitsklassifikator eine Anfrage als Cyber- oder Biologie-Thema ein,
wiederholt Claude Code sie automatisch auf einem älteren Modell (`switchModelsOnFlag`). Nach einem solchen
Hinweis im Transkript mit `/status` prüfen, welches Modell läuft, und bei Bedarf zurückwechseln
(`/model opusplan` oder `/model fable`).

**Subagenten (Agent-Tool):** Jeder ECC-Agent trägt sein Modell im Frontmatter, nicht überschreiben.
- Haiku, effort low: reines Lesen, Suchen, Sortieren, Doku nachschlagen (code-explorer, docs-lookup,
  comment-analyzer, conversation-analyzer, doc-updater, loop-operator, opensource-forker, opensource-packager).
- Sonnet, effort medium: Umsetzung, Build-Fixer, Tests, Refactoring.
- Sonnet, effort high: alle Reviewer, tdd-guide, Performance, Netzwerkdiagnose.
- Fable, effort high: harte Arbeit (planner, architect, spec-miner) und Sicherheitsrelevantes
  (security-reviewer, healthcare-reviewer, network-config-reviewer, opensource-sanitizer).
- Agents ohne eigenes Modell (general-purpose, Plugin-, Workflow- und Team-Agents) laufen über
  `CLAUDE_CODE_SUBAGENT_MODEL` auf Sonnet statt auf dem Hauptmodell (sonst erbt ein Suchagent Fable-Preise).
  Frontmatter und ein beim Aufruf übergebenes `model` haben Vorrang. Braucht ein Unterauftrag mehr, beim
  Aufruf `model: opus` oder `model: fable` mitgeben.

**Kostenregel:** Kosten je erledigter Aufgabe zählen, nicht je Anfrage. Ein billigeres Modell, das zwei
Anläufe braucht, ist teurer. Erst Effort ändern, dann Modell wechseln.

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

## Denktiefe und Plan-Modus

Die aktuellen Modelle (Fable 5.2, Opus 5.5, Sonnet 5.5, Haiku 5.5) denken adaptiv; ein festes Thinking-Budget
(`MAX_THINKING_TOKENS`) wirkt dort nicht. Gesteuert wird über den Effort: `/effort low|medium|high|xhigh` in
der Sitzung, `effort` im Agent-Frontmatter, gespeichert je Modell unter `modelSettings`. Für komplexe Aufgaben:
zuerst Plan-Modus (mit `opusplan` plant dann Opus), dann Effort erhöhen, erst danach das Modell wechseln.

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
