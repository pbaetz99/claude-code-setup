#!/usr/bin/env python3
"""Lokaler MCP-Server fuer Bildgenerierung mit FLUX.1.

Getrennt vom Modell-Routing: Claude Code ruft hier ein Tool auf, der Server
erzeugt lokal ein Bild (kein Token-Verbrauch, keine Daten verlassen den Rechner)
und gibt den Dateipfad zurueck.

Laeuft als eigenstaendiger Prozess; registriert via:
    claude mcp add-json flux '{"command":"<venv>/bin/python","args":["<pfad>/flux-image-server.py"]}'

Umgebung:
    FLUX_MODEL       Standard: black-forest-labs/FLUX.1-schnell (Apache-2.0, kein Gating, schnell).
                     Alternative: black-forest-labs/FLUX.1-dev (bessere Qualitaet, HF-Login noetig).
    FLUX_OUTPUT_DIR  Zielordner fuer PNGs. Standard: ~/flux-output
    FLUX_DEVICE      cuda | cpu | mps. Standard: Autoerkennung.
    FLUX_OFFLOAD     1 = Model-CPU-Offload (spart VRAM, langsamer). Standard bei <24 GB sinnvoll.
    FLUX_STEPS       Standard-Schrittzahl. schnell: 4, dev: ~28.

Abhaengigkeiten siehe requirements.txt.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:  # pragma: no cover - klare Fehlermeldung statt Traceback
    sys.stderr.write(
        "Fehlt: das Paket 'mcp'. Installiere die Abhaengigkeiten aus requirements.txt.\n"
    )
    raise

DEFAULT_MODEL = os.environ.get("FLUX_MODEL", "black-forest-labs/FLUX.1-schnell")
OUTPUT_DIR = Path(os.environ.get("FLUX_OUTPUT_DIR", str(Path.home() / "flux-output")))
DEFAULT_STEPS = int(os.environ.get("FLUX_STEPS", "4"))

mcp = FastMCP("flux")

_pipe = None  # Pipeline wird beim ersten Aufruf geladen und bleibt resident.


def _select_device() -> str:
    forced = os.environ.get("FLUX_DEVICE")
    if forced:
        return forced
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
        if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def _load_pipeline():
    global _pipe
    if _pipe is not None:
        return _pipe
    import torch
    from diffusers import FluxPipeline

    device = _select_device()
    dtype = torch.bfloat16 if device != "cpu" else torch.float32
    pipe = FluxPipeline.from_pretrained(DEFAULT_MODEL, torch_dtype=dtype)

    if os.environ.get("FLUX_OFFLOAD", "0") == "1" and device == "cuda":
        # Spart VRAM: Gewichte wandern bei Bedarf auf die GPU.
        pipe.enable_model_cpu_offload()
    else:
        pipe = pipe.to(device)

    _pipe = pipe
    return _pipe


@mcp.tool()
def generate_image(
    prompt: str,
    width: int = 1024,
    height: int = 1024,
    steps: int = DEFAULT_STEPS,
    seed: int | None = None,
    guidance_scale: float = 0.0,
) -> str:
    """Erzeugt lokal ein Bild aus einem Text-Prompt und speichert es als PNG.

    Gibt den absoluten Pfad der erzeugten Datei zurueck.

    Args:
        prompt: Bildbeschreibung.
        width: Breite in Pixeln (Vielfaches von 16).
        height: Hoehe in Pixeln (Vielfaches von 16).
        steps: Diffusionsschritte. FLUX.1-schnell: 4, FLUX.1-dev: ~28.
        seed: Fester Seed fuer reproduzierbare Ergebnisse, sonst zufaellig.
        guidance_scale: Fuer FLUX.1-schnell 0.0, fuer FLUX.1-dev z. B. 3.5.
    """
    if not prompt or not prompt.strip():
        raise ValueError("prompt darf nicht leer sein.")

    import torch

    pipe = _load_pipeline()
    generator = None
    if seed is not None:
        generator = torch.Generator(device=_select_device()).manual_seed(int(seed))

    result = pipe(
        prompt=prompt,
        width=int(width),
        height=int(height),
        num_inference_steps=int(steps),
        guidance_scale=float(guidance_scale),
        generator=generator,
    )
    image = result.images[0]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = OUTPUT_DIR / f"flux-{stamp}.png"
    image.save(out_path)
    return str(out_path.resolve())


if __name__ == "__main__":
    mcp.run()
