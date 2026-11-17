#!/usr/bin/env python3
"""Expire les anciens builds TestFlight de l'app (sans dépendance).

Garde le build valide le plus récent (celui que les testeurs installent) et expire
tous les autres builds non expirés de l'app. Un build expiré ne peut plus être
installé ; Apple ne permet pas de le supprimer tout à fait.

Usage : asc_builds.py <clé.p8> <key_id> <issuer_id> <bundle_id> [à_garder=1]
"""

import sys

from asc_check import call, jwt


def main() -> None:
    key_path, key_id, issuer, bundle_id = (a.strip() for a in sys.argv[1:5])
    keep = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    token = jwt(key_path, key_id, issuer)

    # /builds avec l'app incluse : évite /apps?filter[bundleId], parfois en panne.
    builds, path = [], (
        "/builds?filter[expired]=false&sort=-uploadedDate&limit=200"
        "&include=app&fields[apps]=bundleId&fields[builds]=version,uploadedDate,processingState,app"
    )
    while path:
        status, data = call(token, "GET", path)
        if status != 200:
            print(f"::warning title=Nettoyage impossible::Liste des builds : HTTP {status}.")
            return
        apps = {a["id"]: a["attributes"].get("bundleId") for a in data.get("included", []) if a["type"] == "apps"}
        for b in data.get("data", []):
            app = (b.get("relationships", {}).get("app", {}).get("data") or {}).get("id")
            if apps.get(app) == bundle_id:
                builds.append(b)
        nxt = data.get("links", {}).get("next")
        path = nxt.split("/v1", 1)[1] if nxt else None

    # Les plus récents d'abord ; seuls les builds valides comptent comme « gardés ».
    builds.sort(key=lambda b: b["attributes"].get("uploadedDate") or "", reverse=True)
    kept = [b for b in builds if b["attributes"].get("processingState") == "VALID"][:keep]
    # Un build encore en traitement chez Apple est le plus neuf : jamais expiré.
    old = [b for b in builds if b not in kept and b["attributes"].get("processingState") != "PROCESSING"]
    for b in kept:
        print(f"Gardé : build {b['attributes'].get('version')} ({(b['attributes'].get('uploadedDate') or '')[:10]}).")
    done = 0
    for b in old:
        status, _ = call(
            token,
            "PATCH",
            f"/builds/{b['id']}",
            {"data": {"type": "builds", "id": b["id"], "attributes": {"expired": True}}},
        )
        v = b["attributes"].get("version")
        if status == 200:
            done += 1
            print(f"Expiré : build {v}.")
        else:
            print(f"::warning::Build {v} non expiré (HTTP {status}).")
    print(f"{done} ancien(s) build(s) expiré(s) sur {len(old)}, {len(kept)} gardé(s).")


if __name__ == "__main__":
    main()
