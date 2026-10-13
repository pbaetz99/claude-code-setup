#!/usr/bin/env python3
"""Lokaler MCP-Server fuer Bildgenerierung mit FLUX.1.

Getrennt vom Modell-Routing: Claude Code ruft hier ein Tool auf, der Server
erzeugt lokal ein Bild (kein Token-Verbrauch, keine Daten verlassen den Rechner)
und gibt den Dateipfad zurueck.

Laeuft als eigenstaendiger Prozess; registriert via:
    claude mcp add --scope user flux -- <venv>/bin/python <pfad>/flux-image-server.py

Umgebung:
    FLUX_MODEL       Standard: black-forest-labs/FLUX.1-schnell (Apache-2.0, kein Gating, schnell).
                     Alternative: black-forest-labs/FLUX.1-dev (bessere Qualitaet, HF-Login noetig).
    FLUX_OUTPUT_DIR  Zielordner fuer PNGs. Standard: ~/flux-output
    FLUX_DEVICE      cuda | cpu. Standard: Autoerkennung.
    FLUX_OFFLOAD     1 (Standard) = Model-CPU-Offload, 0 = alles im VRAM (nur mit >=24 GB).
    FLUX_QUANT       nf4 (Standard, fuer 16-GB-Karten wie RTX 5070 Ti) | none (volles bf16).
    FLUX_FREE_OLLAMA 1 (Standard) = vor jedem Bild laufende Ollama-Modelle aus dem VRAM entladen.
    OLLAMA_HOST_URL  Standard: http://127.0.0.1:11434
    FLUX_STEPS       Standard-Schrittzahl. Ohne Angabe: schnell 4, dev 28.

Aufruf mit --warmup laedt das Modell einmal (Download ~35 GB in den HF-Cache) und beendet sich.

Abhaengigkeiten siehe requirements.txt.
"""

from __future__ import annotations

import contextlib
import json
import os
import sys
import urllib.request
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
IS_SCHNELL = "schnell" in DEFAULT_MODEL.lower()
OUTPUT_DIR = Path(os.environ.get("FLUX_OUTPUT_DIR", str(Path.home() / "flux-output")))
DEFAULT_STEPS = int(os.environ.get("FLUX_STEPS", "4" if IS_SCHNELL else "28"))
DEFAULT_GUIDANCE = 0.0 if IS_SCHNELL else 3.5
QUANT = os.environ.get("FLUX_QUANT", "nf4").lower()  # nf4 (16-GB-Karten) | none (bf16, >=24 GB)
OLLAMA_URL = os.environ.get("OLLAMA_HOST_URL", "http://127.0.0.1:11434").rstrip("/")

MIN_SIDE, MAX_SIDE, SIDE_STEP = 256, 2048, 16
MIN_STEPS, MAX_STEPS = 1, 50

mcp = FastMCP("flux")

_pipe = None  # Pipeline wird beim ersten Aufruf geladen und bleibt resident (Gewichte im RAM).


def _select_device() -> str:
    forced = os.environ.get("FLUX_DEVICE")
    if forced:
        return forced
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass
    return "cpu"


def _free_ollama_vram() -> None:
    """Entlaedt laufende Ollama-Modelle, damit Flux die GPU fuer sich hat.

    Auf einer 16-GB-Karte passen Qwen-30B und Flux nicht gleichzeitig in den VRAM.
    Ollama laedt das Modell bei der naechsten Coding-Anfrage automatisch neu.
    """
    if os.environ.get("FLUX_FREE_OLLAMA", "1") != "1":
        return
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL}/api/ps", timeout=3) as resp:
            loaded = json.load(resp).get("models", [])
        for model in loaded:
            payload = json.dumps({"model": model["name"], "keep_alive": 0}).encode()
            req = urllib.request.Request(
                f"{OLLAMA_URL}/api/generate", data=payload, headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=30) as unload:
                unload.read()
    except Exception as err:  # Ollama nicht erreichbar -> Flux laeuft trotzdem, ggf. knapper VRAM
        sys.stderr.write(f"flux: Ollama-VRAM nicht freigegeben ({err})\n")


def _quantized_components(torch, dtype) -> dict:
    """16-GB-Profil: Transformer und T5-Encoder in NF4 (beide bleiben offload-faehig)."""
    from diffusers import BitsAndBytesConfig as DiffusersBnbConfig
    from diffusers import FluxTransformer2DModel
    from transformers import BitsAndBytesConfig as TransformersBnbConfig
    from transformers import T5EncoderModel

    nf4 = dict(load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_compute_dtype=torch.bfloat16)
    return {
        "transformer": FluxTransformer2DModel.from_pretrained(
            DEFAULT_MODEL,
            subfolder="transformer",
            quantization_config=DiffusersBnbConfig(**nf4),
            torch_dtype=dtype,
        ),
        "text_encoder_2": T5EncoderModel.from_pretrained(
            DEFAULT_MODEL,
            subfolder="text_encoder_2",
            quantization_config=TransformersBnbConfig(**nf4),
            torch_dtype=dtype,
        ),
    }


def _load_pipeline():
    global _pipe
    if _pipe is not None:
        return _pipe
    import torch
    from diffusers import FluxPipeline

    device = _select_device()
    dtype = torch.bfloat16 if device != "cpu" else torch.float32
    extra = _quantized_components(torch, dtype) if device == "cuda" and QUANT == "nf4" else {}
    pipe = FluxPipeline.from_pretrained(DEFAULT_MODEL, torch_dtype=dtype, **extra)

    if device == "cuda" and os.environ.get("FLUX_OFFLOAD", "1") == "1":
        # Nur die gerade rechnende Komponente liegt im VRAM; Rest im RAM (64 GB reichen).
        pipe.enable_model_cpu_offload()
    else:
        pipe = pipe.to(device)

    _pipe = pipe
    return _pipe


def _validate(prompt: str, width: int, height: int, steps: int) -> None:
    if not prompt or not prompt.strip():
        raise ValueError("prompt darf nicht leer sein.")
    for name, side in (("width", width), ("height", height)):
        if not MIN_SIDE <= side <= MAX_SIDE or side % SIDE_STEP:
            raise ValueError(f"{name} muss zwischen {MIN_SIDE} und {MAX_SIDE} liegen und durch {SIDE_STEP} teilbar sein.")
    if not MIN_STEPS <= steps <= MAX_STEPS:
        raise ValueError(f"steps muss zwischen {MIN_STEPS} und {MAX_STEPS} liegen.")


@mcp.tool()
def generate_image(
    prompt: str,
    width: int = 1024,
    height: int = 1024,
    steps: int | None = None,
    seed: int | None = None,
    guidance_scale: float | None = None,
) -> str:
    """Erzeugt lokal ein Bild aus einem Text-Prompt und speichert es als PNG.

    Gibt den absoluten Pfad der erzeugten Datei zurueck.

    Args:
        prompt: Bildbeschreibung.
        width: Breite in Pixeln (256-2048, Vielfaches von 16).
        height: Hoehe in Pixeln (256-2048, Vielfaches von 16).
        steps: Diffusionsschritte (1-50). Standard: schnell 4, dev 28.
        seed: Fester Seed fuer reproduzierbare Ergebnisse, sonst zufaellig.
        guidance_scale: Standard: schnell 0.0, dev 3.5.
    """
    steps = DEFAULT_STEPS if steps is None else int(steps)
    guidance = DEFAULT_GUIDANCE if guidance_scale is None else float(guidance_scale)
    _validate(prompt, int(width), int(height), steps)

    import torch

    _free_ollama_vram()
    # stdout gehoert dem MCP-Protokoll: Bibliotheksausgaben auf stderr umlenken.
    with contextlib.redirect_stdout(sys.stderr):
        pipe = _load_pipeline()
        generator = torch.Generator("cpu").manual_seed(int(seed)) if seed is not None else None
        image = pipe(
            prompt=prompt,
            width=int(width),
            height=int(height),
            num_inference_steps=steps,
            guidance_scale=guidance,
            generator=generator,
        ).images[0]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    out_path = OUTPUT_DIR / f"flux-{stamp}.png"
    image.save(out_path)
    return str(out_path.resolve())


if __name__ == "__main__":
    if "--warmup" in sys.argv:
        with contextlib.redirect_stdout(sys.stderr):
            _load_pipeline()
        sys.stderr.write("flux: Modell geladen und im HF-Cache.\n")
    else:
        mcp.run()
