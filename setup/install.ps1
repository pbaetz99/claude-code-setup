<#
Richtet dieses Claude-Code-Setup auf einem Windows-Rechner ein.
macOS, Linux, WSL: setup/install.sh verwenden.

Was passiert:
  1. ~/.claude wird zum Checkout dieses Repos. Bestehende Konfigdateien werden vorher
     nach ~/.claude/backups/vor-setup-<Zeit>/ gesichert.
  2. Marktplaetze und Plugins aus setup/plugins.json werden installiert; was auf dem
     Quellrechner deaktiviert war, bleibt deaktiviert.
  3. Sprachserver (TypeScript, Pyright) werden global per npm installiert, damit die
     LSP-Plugins nicht leer laufen.
Was NICHT passiert: keine Zugangsdaten, keine Sitzungen, kein ~/.claude.json. Anmelden
musst du einmal selbst mit `claude`.

Aufruf:  powershell -ExecutionPolicy Bypass -File setup/install.ps1 [-Repo <url>]
#>
param(
    [string]$Repo = "https://github.com/pbaetz99/claude-code-setup.git"
)
$ErrorActionPreference = "Stop"
$Ziel = Join-Path $env:USERPROFILE ".claude"
$Stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

function Pruefe-Befehl($name, $hinweis) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Host "FEHLT: $name. $hinweis" -ForegroundColor Red
        exit 1
    }
}
Pruefe-Befehl git  "winget install Git.Git"
Pruefe-Befehl node "winget install OpenJS.NodeJS.LTS (ECC-Hooks brauchen Node 18+)"
Pruefe-Befehl npm  "kommt mit Node"
Pruefe-Befehl claude "winget install Anthropic.ClaudeCode"
Pruefe-Befehl python "winget install Python.Python.3.12 (fuer setup/export-plugins.py)"

New-Item -ItemType Directory -Force -Path $Ziel | Out-Null
if (-not (Test-Path (Join-Path $Ziel ".git"))) {
    $Sicherung = Join-Path $Ziel "backups\vor-setup-$Stamp"
    Write-Host "== Sichere bestehende Konfiguration nach $Sicherung"
    New-Item -ItemType Directory -Force -Path $Sicherung | Out-Null
    foreach ($f in @("settings.json", "AGENTS.md", "agents", "commands", "skills", "rules", "hooks", "scripts", "mcp-configs")) {
        $quelle = Join-Path $Ziel $f
        if (Test-Path $quelle) { Copy-Item -Recurse -Force $quelle $Sicherung }
    }
    git -C $Ziel init -q
    git -C $Ziel remote add origin $Repo
}
Write-Host "== Hole $Repo"
git -C $Ziel fetch -q origin
git -C $Ziel checkout -q -f -B main origin/main
git -C $Ziel config core.autocrlf false
Write-Host "== Konfiguration steht in $Ziel"

$Manifest = Get-Content (Join-Path $Ziel "setup\plugins.json") -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "== Marktplaetze"
foreach ($m in $Manifest.marketplaces.PSObject.Properties) {
    $src = $m.Value
    $quelle = if ($src.repo) { $src.repo } else { $src.url }
    if (-not $quelle) { continue }
    & claude plugin marketplace add $quelle *> $null
    if ($?) { Write-Host "   + $quelle" } else { Write-Host "   (schon da oder fehlgeschlagen) $quelle" }
}

Write-Host "== Plugins (Nutzer-Ebene)"
foreach ($p in $Manifest.plugins_user) {
    & claude plugin install -y $p.id *> $null
    if ($?) { Write-Host "   + $($p.id)" } else { Write-Host "   (fehlgeschlagen) $($p.id)" }
    if (-not $p.enabled) {
        & claude plugin disable $p.id *> $null
        Write-Host "     deaktiviert, wie auf dem Quellrechner"
    }
}
# Die claude-plugin-Befehle schreiben settings.json neu und streichen dabei "autoUpdate" der
# Marktplaetze. Repo-Stand zuruecksetzen; self-update.sh braucht ausserdem einen sauberen Checkout.
git -C $Ziel checkout -- settings.json

Write-Host "== Sprachserver fuer die LSP-Plugins (npm global)"
& npm install -g @($Manifest.npm_global) *> $null
if ($?) { Write-Host "   + $($Manifest.npm_global -join ', ')" } else { Write-Host "   (npm install fehlgeschlagen, LSP-Plugins laufen dann leer)" }

Write-Host ""
Write-Host "Fertig. Noch zu tun:"
Write-Host " - claude starten und anmelden."
Write-Host " - Projektgebundene Plugins (setup/plugins.json, plugins_projekt) im Projektordner mit"
Write-Host "   claude plugin install --scope project <id> nachziehen, falls gewuenscht."
Write-Host " - claude.ai-Konto-Plugins ($($Manifest.claude_ai_konto_plugins -join ', ')) haengen am Login."
