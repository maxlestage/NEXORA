#!/usr/bin/env python3
"""Récupère les derniers modèles d'IA sur internet et met à jour le catalogue de NEXORA.

Sources, toutes publiques et sans clé :
- models.dev : base ouverte des modèles de chaque fournisseur (date de sortie, prix,
  contexte, raisonnement) ;
- OpenRouter (/api/v1/models) : la liste en direct, souvent à jour le jour même d'une
  sortie. Elle complète OpenRouter et signale les toutes dernières sorties d'Anthropic,
  OpenAI, Google, xAI et Mistral que models.dev n'a pas encore ;
- Pollinations : ses modèles gratuits.
Écrit le même fichier à deux endroits :
- app/assets/models.json : livré avec l'app ;
- site/public/models.json : publié sur le site, que l'app relit chaque jour pour avoir
  les nouveaux modèles sans attendre une mise à jour.

Lancé toutes les 6 heures par .github/workflows/models.yml, ou à la main :
    python3 .github/scripts/update_models.py
Sans dépendance : python3 suffit. Affiche à la fin les toutes dernières sorties.
"""

import json
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
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


# Préfixe OpenRouter → fournisseur NEXORA, et passage de l'identifiant OpenRouter à
# celui de l'API du fournisseur (Anthropic écrit 5-2 là où OpenRouter écrit 5.2).
# Seulement les fournisseurs dont les identifiants se correspondent de façon sûre.
OPENROUTER_NATIVE = {
    "anthropic": ("anthropic", lambda i: i.replace(".", "-")),
    "openai": ("openai", lambda i: i),
    "google": ("gemini", lambda i: i),
    "x-ai": ("xai", lambda i: i),
}

# Une sortie détectée sur OpenRouter n'est ajoutée chez le fournisseur que si elle est
# récente (les anciennes sont déjà dans models.dev, ou retirées).
FRESH_DAYS = 45


def norm(i: str) -> str:
    return re.sub(r"[^a-z0-9]", "", i.lower())


def openrouter_entry(m: dict) -> dict | None:
    arch = m.get("architecture") or {}
    if "text" not in (arch.get("output_modalities") or ["text"]):
        return None
    if "text" not in (arch.get("input_modalities") or ["text"]):
        return None
    pricing = m.get("pricing") or {}
    created = m.get("created") or 0
    e = {
        "id": m["id"],
        "name": m.get("name") or m["id"],
        "release": datetime.fromtimestamp(created, timezone.utc).strftime("%Y-%m-%d") if created else "",
    }
    try:
        e["in"] = round(float(pricing.get("prompt") or 0) * 1e6, 4)
        e["out"] = round(float(pricing.get("completion") or 0) * 1e6, 4)
    except (TypeError, ValueError):
        pass
    if m.get("context_length"):
        e["context"] = int(m["context_length"])
    # Un modèle qui ne rend que du texte (pas d'image, de vidéo ou de son).
    e["_text"] = (arch.get("output_modalities") or ["text"]) == ["text"]
    params = m.get("supported_parameters") or []
    if "reasoning" in params or "include_reasoning" in params:
        e["reasoning"] = True
    if "tools" in params:
        e["tools"] = True
    return e


def merge_openrouter(providers: dict) -> list[str]:
    """Ajoute la liste en direct d'OpenRouter. Rend les modèles ajoutés."""
    try:
        live = fetch("https://openrouter.ai/api/v1/models").get("data") or []
    except Exception as e:  # source facultative
        print(f"OpenRouter indisponible : {e}")
        return []
    added = []
    fresh = (datetime.now(timezone.utc) - timedelta(days=FRESH_DAYS)).strftime("%Y-%m-%d")
    entries = [e for e in (openrouter_entry(m) for m in live if m.get("id")) if e]
    # OpenRouter lui-même : la liste en direct complète models.dev.
    mine = providers.setdefault("openrouter", [])
    known = {norm(e["id"]) for e in mine}
    for e in entries:
        if e["id"].endswith(":batch") or norm(e["id"]) in known:
            continue
        mine.append(e)
        known.add(norm(e["id"]))
        if e["release"] >= fresh:
            added.append(f"openrouter/{e['id']}")
    # Les fournisseurs directs : seulement les sorties récentes encore absentes.
    for e in entries:
        head, _, rest = e["id"].partition("/")
        if head not in OPENROUTER_NATIVE or ":" in rest or e["release"] < fresh or not e["_text"]:
            continue
        ours, to_native = OPENROUTER_NATIVE[head]
        native = to_native(rest)
        lst = providers.setdefault(ours, [])
        if any(norm(x["id"]) == norm(native) or norm(x["id"]) == norm(rest) for x in lst):
            continue
        name = e["name"].split(": ", 1)[-1]
        lst.append({**e, "id": native, "name": name})
        added.append(f"{ours}/{native}")
    return added


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
        if models:
            providers[ours] = models
    added = merge_openrouter(providers)
    for ours, models in list(providers.items()):
        for e in models:
            e.pop("_text", None)
        models.sort(key=lambda e: (e["release"], e["id"]), reverse=True)
        if ours == "openrouter":
            free = [e for e in models if e["id"].endswith(":free")]
            rest = [e for e in models if not e["id"].endswith(":free")]
            models = free + rest[: max(0, LIMIT_OPENROUTER - len(free))]
            models.sort(key=lambda e: (e["release"], e["id"]), reverse=True)
        else:
            models = models[:LIMIT]
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
        "source": "models.dev + openrouter",
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
    if added:
        print(f"Trouvés sur OpenRouter avant models.dev : {', '.join(added[:20])}")
    latest = sorted(
        ((m["release"], p, m["id"]) for p, ms in providers.items() for m in ms if m["release"]),
        reverse=True,
    )
    seen = set()
    print("Toutes dernières sorties :")
    for release, p, i in latest:
        key = norm(i.split("/")[-1].split(":")[0])
        if key in seen:
            continue
        seen.add(key)
        print(f"  {release}  {p:12} {i}")
        if len(seen) == 20:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
