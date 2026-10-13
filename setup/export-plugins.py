"""Schreibt setup/plugins.json aus dem tatsächlichen Plugin-Stand dieses Rechners.

Aufruf (aus ~/.claude):  python -I setup/export-plugins.py

Warum eine erzeugte Datei und keine handgepflegte: Was auseinanderlaufen kann, läuft
auseinander. Die Quelle der Wahrheit ist, was `claude plugin install` wirklich
eingetragen hat (plugins/installed_plugins.json), welche Plugins in settings.json
ab- oder angeschaltet sind und welche Marktplätze bekannt sind. Nach jeder
Plugin-Änderung einmal laufen lassen und mit committen.
"""
import datetime
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
INSTALLED = ROOT / "plugins" / "installed_plugins.json"
MARKETPLACES = ROOT / "plugins" / "known_marketplaces.json"
SETTINGS = ROOT / "settings.json"
ZIEL = ROOT / "setup" / "plugins.json"

# Plugins, die am claude.ai-Konto hängen (Login), nicht am Rechner. Nur zur Information.
KONTO_PLUGINS = ["humanizer", "figma", "design", "engineering", "product-management", "data"]


def lade(pfad: pathlib.Path) -> dict:
    return json.loads(pfad.read_text(encoding="utf-8"))


def main() -> None:
    installiert = lade(INSTALLED)["plugins"]
    bekannt = lade(MARKETPLACES)
    aktiv = lade(SETTINGS).get("enabledPlugins", {})

    nutzer, projekt = [], []
    for plugin_id, eintraege in sorted(installiert.items()):
        for e in eintraege:
            satz = {"id": plugin_id, "version": e.get("version"), "enabled": aktiv.get(plugin_id, True)}
            if e.get("scope") == "user":
                nutzer.append(satz)
            else:
                projekt.append({**satz, "projekt": e.get("projectPath")})

    ergebnis = {
        "_hinweis": "Erzeugt von setup/export-plugins.py. Nicht von Hand pflegen, sondern neu erzeugen.",
        "erzeugt_am": datetime.date.today().isoformat(),
        "marketplaces": {name: m["source"] for name, m in sorted(bekannt.items())},
        "plugins_user": nutzer,
        "plugins_projekt": projekt,
        "claude_ai_konto_plugins": KONTO_PLUGINS,
        "npm_global": ["typescript-language-server", "typescript", "pyright"],
    }
    ZIEL.write_text(json.dumps(ergebnis, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{ZIEL}: {len(nutzer)} Nutzer-Plugins, {len(projekt)} Projekt-Plugins, "
          f"{len(ergebnis['marketplaces'])} Marktplätze")


if __name__ == "__main__":
    main()
