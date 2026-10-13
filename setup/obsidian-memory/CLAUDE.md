# Gedächtnis: Obsidian-Vault

Langzeitgedächtnis ist der Obsidian-Vault aus `CLAUDE_OBSIDIAN_VAULT` (Plugin claude-obsidian).
Beim Sitzungsstart lädt ein Hook `wiki/hot.md` automatisch in den Kontext.

## Abrufen

- Bevor du nach früheren Entscheidungen, Vorlieben oder Projektwissen fragst: erst mit
  `wiki-query` im Vault nachsehen.
- `hot.md` ist der aktuelle Kurzstand; Details stehen in den verlinkten Notizen.

## Speichern

- Am Ende einer Aufgabe mit bleibendem Wert (Architekturentscheidung, gelöster
  Fehler mit nicht offensichtlicher Ursache, neue Vorliebe des Nutzers, Runbook)
  `/save` anbieten und kurz sagen, was gespeichert würde. Erst nach Zustimmung speichern.
- Eine Notiz je Thema, knapp, mit Datum (absolut, nicht „gestern“) und Links auf
  verwandte Notizen. Lieber bestehende Notiz aktualisieren als eine doppelte anlegen.
- Nicht speichern: was schon im Repo, in der Git-Historie oder in CLAUDE.md steht,
  Zwischenstände einer einzelnen Sitzung, Mitschriften.

## Niemals in den Vault

Passwörter, API-Keys, Tokens, Zugangsdaten, Patientendaten (PHI), personenbezogene
Daten Dritter, interne Hostnamen oder IP-Adressen.

## Verhältnis zum eingebauten Memory

Das eingebaute Auto-Memory von Claude Code bleibt für kurze Arbeitsnotizen. Was
du langfristig wissen musst oder was der Nutzer selbst nachlesen will, gehört in den Vault.
