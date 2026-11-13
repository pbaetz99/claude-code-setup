---
description: Recommend the best model tier for the current task based on complexity, risk, and budget.
---

# Model Route Command

Recommend the best model tier for the current task by complexity and budget.

## Usage

`/model-route [task-description] [--budget low|med|high]`

## Routing Heuristic

- `haiku` (0,10/0,50 USD je MTok, über 100k Prompt-Tokens 0,50/2,50): deterministische, risikoarme mechanische Arbeit, Suchen, Lesen
- `sonnet` (2/10): Standard für Umsetzung, Refactoring, Tests; Reviews mit effort high
- `opus` (4/20): komplexe Umsetzung und unklare Anforderungen
- `fable` (Fable 5.2, 8/40): harte Arbeit (Architektur, Planung, Root-Cause) und alles Sicherheitsrelevante (Security-Review, Auth, Secrets, PHI)
- Hauptsession-Standard ist `opusplan` (Opus plant, Sonnet baut); Effort zuerst ändern, dann Modell wechseln
- Als Cyber- oder Biologie-Thema geflaggte Anfragen wiederholt Claude Code automatisch auf einem älteren Modell; danach mit `/status` prüfen, welches Modell läuft

## Required Output

- recommended model
- confidence level
- why this model fits
- fallback model if first attempt fails

## Arguments

$ARGUMENTS:
- `[task-description]` optional free-text
- `--budget low|med|high` optional
