#!/usr/bin/env python3
"""Fait de la place dans les certificats de signature avant de compiler.

À chaque build, Xcode (signature automatique avec la clé d'API) crée des certificats
« Created via API » sur la machine jetable de GitHub Actions. Apple limite leur nombre :
au bout de quelques dizaines de builds, il refuse d'en créer (« Your account has reached
the maximum number of certificates »). Ce script révoque ceux que l'automatisation a
créés lors des builds précédents ; il ne touche pas aux autres (ceux d'un Mac, par
exemple). Révoquer un certificat de distribution n'affecte pas les versions déjà
publiées sur TestFlight ou l'App Store.

Usage : asc_certs.py <clé.p8> <key_id> <issuer_id>
"""

import sys

from asc_check import call, jwt

TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT", "DISTRIBUTION", "IOS_DISTRIBUTION"}


def made_by_ci(attrs: dict) -> bool:
    text = f"{attrs.get('name', '')} {attrs.get('displayName', '')}".lower()
    return "via api" in text


def main() -> None:
    key_path, key_id, issuer = (a.strip() for a in sys.argv[1:4])
    token = jwt(key_path, key_id, issuer)
    status, data = call(token, "GET", "/certificates?limit=200")
    if status != 200:
        print(f"::warning title=Certificats::Liste illisible ({status}), on continue.")
        return
    certs = data.get("data", [])
    print(f"{len(certs)} certificat(s) sur le compte :")
    revoked = kept = 0
    for c in certs:
        a = c.get("attributes", {})
        kind = a.get("certificateType", "?")
        label = a.get("displayName") or a.get("name") or "?"
        if kind in TYPES and made_by_ci(a):
            st, _ = call(token, "DELETE", f"/certificates/{c['id']}")
            ok = st in (200, 204)
            revoked += ok
            print(f"  - {kind} « {label} » : {'révoqué' if ok else f'non révoqué ({st})'}")
        else:
            kept += 1
            expire = (a.get("expirationDate") or "?")[:10]
            print(f"  - {kind} « {label} » (expire {expire}) : gardé")
    print(f"Révoqués : {revoked} · gardés : {kept}.")
    if revoked == 0 and kept > 0:
        print(
            "::warning title=Certificats::Aucun certificat « Created via API » à révoquer. "
            "Si Apple refuse encore d'en créer, révoquez les anciens sur "
            "developer.apple.com → Certificates."
        )


if __name__ == "__main__":
    main()
