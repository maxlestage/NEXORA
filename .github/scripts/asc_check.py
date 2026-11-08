#!/usr/bin/env python3
"""Vérifie App Store Connect avant de compiler l'app iOS (sans dépendance).

- la clé d'API est acceptée par Apple (sinon : Key ID, Issuer ID ou clé incorrects) ;
- l'identifiant de l'app (bundle ID) existe, et il est enregistré s'il manque ;
- la fiche de l'app existe dans App Store Connect (Apple ne permet pas de la créer
  par l'API : il faut la créer une fois dans le site).

Usage : asc_check.py <clé.p8> <key_id> <issuer_id> <bundle_id> <nom>
"""

import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """Signature ECDSA DER (sortie d'openssl) → r||s sur 64 octets (format JWT)."""
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        out += sig[i + 2 : i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return out


def jwt(key_path: str, key_id: str, issuer: str) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps(
            {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    sig = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(sig))}"


def call(token: str, method: str, path: str, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def error(title: str, message: str) -> None:
    print(f"::error title={title}::{message}")
    sys.exit(1)


def main() -> None:
    key_path, key_id, issuer, bundle_id, name = sys.argv[1:6]
    token = jwt(key_path, key_id, issuer)
    q = urllib.parse.quote(bundle_id)

    status, data = call(token, "GET", f"/bundleIds?filter[identifier]={q}&limit=200")
    if status == 401:
        error(
            "Clé d'API refusée par Apple",
            "Vérifiez que ASC_KEY_ID est le Key ID de cette clé (les caractères après "
            "AuthKey_ dans le nom du fichier) et que ASC_ISSUER_ID est l'Issuer ID affiché "
            "au-dessus du tableau des clés (Users and Access → Integrations → App Store Connect API).",
        )
    if status == 403:
        error(
            "Droits insuffisants",
            "La clé d'API doit avoir le rôle Admin (ou App Manager) pour enregistrer "
            "l'identifiant et créer les certificats.",
        )
    if status != 200:
        error("App Store Connect", f"Réponse inattendue ({status}) : {json.dumps(data)[:300]}")

    exact = [b for b in data.get("data", []) if b["attributes"]["identifier"] == bundle_id]
    if exact:
        print(f"Identifiant {bundle_id} : déjà enregistré.")
    else:
        status, data = call(
            token,
            "POST",
            "/bundleIds",
            {
                "data": {
                    "type": "bundleIds",
                    "attributes": {"identifier": bundle_id, "name": name, "platform": "IOS"},
                }
            },
        )
        if status not in (200, 201):
            error(
                "Identifiant non enregistré",
                f"Apple refuse d'enregistrer {bundle_id} ({status}) : "
                f"{json.dumps(data.get('errors', data))[:300]}",
            )
        print(f"Identifiant {bundle_id} : enregistré.")

    status, data = call(token, "GET", f"/apps?filter[bundleId]={q}")
    if status == 200 and data.get("data"):
        app = data["data"][0]["attributes"]
        print(f"Fiche App Store Connect : « {app.get('name')} » trouvée.")
        return
    error(
        "Fiche de l'app à créer",
        f"L'identifiant {bundle_id} est prêt. Créez maintenant la fiche : App Store Connect → "
        f"Apps → + → Nouvelle app → iOS, nom {name}, identifiant de lot « {name} - {bundle_id} », "
        "UGS nexora, accès complet → Créer. Puis relancez ce workflow.",
    )


if __name__ == "__main__":
    main()
