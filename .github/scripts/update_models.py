#!/usr/bin/env python3
"""Récupère les derniers modèles d'IA sur internet et met à jour le catalogue de NEXORA.

Source : models.dev (base ouverte des modèles de chaque fournisseur : date de sortie,
prix, contexte, raisonnement), plus la liste publique de Pollinations. Écrit le même
fichier à deux endroits :
- app/assets/models.json : livré avec l'app ;
- site/public/models.json : publié sur le site, que l'app relit chaque jour pour avoir
  les nouveaux modèles sans attendre une mise à jour.

Lancé chaque jour par .github/workflows/models.yml. Sans dépendance : python3 suffit.
"""

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = [ROOT / "app/assets/models.json", ROOT / "site/public/models.json"]

# Fournisseur NEXORA → fournisseur models.dev (et filtre éventuel sur l'identifiant).
PROVIDERS = {
    "anthropic": ("anthropic", None),
    "openai": ("openai", None),
    "gemini": ("google", None),
    "mistral": ("mistral", None),
    "codestral": ("mistral", "codestral"),
    "groq": ("groq", None),
    "cerebras": ("cerebras", None),
    "openrouter": ("openrouter", None),
    "deepseek": ("deepseek", None),
    "xai": ("xai", None),
    "perplexity": ("perplexity", None),
    "together": ("togetherai", None),
    "nvidia": ("nvidia", None),
    "sambanova": ("sambanova", None),
    "cohere": ("cohere", None),
    "cloudflare": ("cloudflare-workers-ai", None),
    "huggingface": ("huggingface", None),
    "ollama-cloud": ("ollama-cloud", None),
}

# Modèles gardés par fournisseur (les plus récents d'abord). OpenRouter en a des
# centaines : on garde les plus récents et tous les gratuits.
LIMIT = 40
LIMIT_OPENROUTER = 120


def fetch(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "nexora-models-updater"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def is_chat(m: dict) -> bool:
    mods = m.get("modalities") or {}
    out = mods.get("output") or ["text"]
    inp = mods.get("input") or ["text"]
    name = (m.get("id", "") + " " + m.get("name", "")).lower()
    if any(w in name for w in ("embed", "tts", "whisper", "transcri", "moderation", "rerank", "image-gen", "dall-e")):
        return False
    return "text" in out and "text" in inp


def entry(m: dict) -> dict:
    cost = m.get("cost") or {}
    limit = m.get("limit") or {}
    e = {
        "id": m["id"],
        "name": m.get("name") or m["id"],
        "release": m.get("release_date") or m.get("last_updated") or "",
    }
    if "input" in cost or "output" in cost:
        e["in"] = float(cost.get("input") or 0)
        e["out"] = float(cost.get("output") or 0)
    if limit.get("context"):
        e["context"] = int(limit["context"])
    if m.get("reasoning"):
        e["reasoning"] = True
    if m.get("tool_call"):
        e["tools"] = True
    return e


def main() -> int:
    db = fetch("https://models.dev/api.json")
    providers: dict = {}
    for ours, (theirs, contains) in PROVIDERS.items():
        src = (db.get(theirs) or {}).get("models") or {}
        models = [
            entry(m)
            for m in src.values()
            if is_chat(m) and (contains is None or contains in m["id"])
            and not m.get("status") == "deprecated"
        ]
        models.sort(key=lambda e: (e["release"], e["id"]), reverse=True)
        if ours == "openrouter":
            free = [e for e in models if e["id"].endswith(":free")]
            rest = [e for e in models if not e["id"].endswith(":free")]
            models = free + rest[: max(0, LIMIT_OPENROUTER - len(free))]
            models.sort(key=lambda e: (e["release"], e["id"]), reverse=True)
        else:
            models = models[:LIMIT]
        if models:
            providers[ours] = models
    try:
        poll = fetch("https://text.pollinations.ai/models")
        providers["pollinations"] = [
            {"id": m["name"], "name": m.get("description") or m["name"], "release": "", "in": 0.0, "out": 0.0}
            for m in poll
            if isinstance(m, dict) and m.get("name") and "text" in (m.get("output_modalities") or ["text"])
        ]
    except Exception as e:  # liste facultative
        print(f"Pollinations indisponible : {e}")

    data = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "models.dev",
        "providers": providers,
    }
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    changed = False
    for path in OUT:
        old = path.read_text() if path.exists() else ""
        # La date seule ne compte pas comme un changement.
        strip = lambda s: json.dumps({k: v for k, v in json.loads(s).items() if k != "updated"}, sort_keys=True) if s else ""
        if strip(old) != strip(text):
            path.write_text(text + "\n")
            changed = True
    total = sum(len(v) for v in providers.values())
    print(f"{total} modèles chez {len(providers)} fournisseurs ({'mis à jour' if changed else 'rien de neuf'}).")
    for p, ms in sorted(providers.items()):
        print(f"  {p:14} {len(ms):3}  derniers : {', '.join(m['id'] for m in ms[:3])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
