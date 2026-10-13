---
description: Erzwingt das lokale Modell (Qwen via Ollama) fuer diese Aufgabe. Nur wirksam, wenn Claude Code ueber den claude-code-router (ccr code) laeuft.
argument-hint: [aufgabe]
---

[[LOKAL]]

Bearbeite die folgende Aufgabe mit dem lokalen Modell (Qwen-Coder). Wenn keine
Aufgabe angegeben ist, verarbeite die bisherige Unterhaltung lokal weiter.

Aufgabe: $ARGUMENTS

<!--
Hinweis: Das Sentinel [[LOKAL]] oben wird vom Custom-Router des
claude-code-router erkannt und zwingt den Request auf Ollama/Qwen.

- Wirkt nur bei Sitzungen, die ueber `ccr code` gestartet wurden, nicht bei nativem `claude`.
- Gilt fuer diesen Aufruf. Fuer einen dauerhaften Wechsel in der Sitzung stattdessen
  den ccr-eigenen Befehl nutzen: /model ollama,qwen3-coder:30b
-->
