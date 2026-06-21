#!/usr/bin/env python3
"""
bigset_routes.py — BigSet outbound data-discovery router (additive).

Drop this file in ~/sovereign alongside sovereign_unified_l402.py.
It defines a router named `bigset`. Your main file mounts it with one
include_router() line. Nothing in your existing file is removed or
renamed — this only adds.

Import is side-effect free: no network calls happen until a route is
actually hit, so importing this never blocks startup.
"""

import os
import json
import time
import base64
import pathlib
import requests
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

# --- config: same ~/sovereign + LND layout your main file uses ---
HOME = pathlib.Path(os.path.expanduser("~"))
EVENT_SPINE = HOME / "sovereign" / "ledger" / "event_spine.jsonl"

LND_REST = os.environ.get("LND_REST", "https://127.0.0.1:8080")
LND_MACAROON = os.environ.get(
    "LND_MACAROON",
    str(HOME / ".lnd" / "data" / "chain" / "bitcoin" / "mainnet" / "admin.macaroon"),
)
LND_TLS_CERT = os.environ.get("LND_TLS_CERT", str(HOME / ".lnd" / "tls.cert"))
L402_PRICE = int(os.environ.get("L402_PRICE_SATS", "100"))


def _spine(event_type: str, payload: dict) -> None:
    try:
        EVENT_SPINE.parent.mkdir(parents=True, exist_ok=True)
        with open(EVENT_SPINE, "a") as fh:
            fh.write(json.dumps({"ts": time.time(), "type": event_type,
                                  "payload": payload}) + "\n")
    except Exception:
        pass  # spine logging must never break a request


def _lnd_headers() -> dict:
    with open(LND_MACAROON, "rb") as fh:
        return {"Grpc-Metadata-macaroon": fh.read().hex()}


def _create_invoice(memo: str):
    r = requests.post(f"{LND_REST}/v1/invoices", headers=_lnd_headers(),
                       json={"value": str(L402_PRICE), "memo": memo},
                       verify=LND_TLS_CERT, timeout=10)
    r.raise_for_status()
    d = r.json()
    return d["payment_request"], base64.b64decode(d["r_hash"]).hex()


def _invoice_settled(r_hash_hex: str) -> bool:
    r = requests.get(f"{LND_REST}/v1/invoice/{r_hash_hex}",
                      headers=_lnd_headers(), verify=LND_TLS_CERT, timeout=10)
    r.raise_for_status()
    return r.json().get("settled", False)


def _l402_ok(request: Request) -> bool:
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("L402 "):
        return False
    try:
        token = auth.split("L402 ", 1)[1]
        r_hash_hex = base64.b64decode(token.split(":", 1)[0]).decode()
        return _invoice_settled(r_hash_hex)
    except Exception:
        return False


def _challenge(memo: str) -> JSONResponse:
    pr, r_hash = _create_invoice(memo)
    _spine("l402_challenge", {"r_hash": r_hash, "price": L402_PRICE})
    return JSONResponse(
        status_code=402,
        headers={"WWW-Authenticate":
                 f'L402 macaroon="{base64.b64encode(r_hash.encode()).decode()}", '
                 f'invoice="{pr}"'},
        content={"error": "payment_required", "invoice": pr,
                 "price_sats": L402_PRICE, "r_hash": r_hash},
    )


# --- the router your main file mounts ---
bigset = APIRouter(prefix="/bigset", tags=["bigset"])


@bigset.get("/status")
def bigset_status():
    return {"bigset": "online", "mode": "outbound_discovery"}


@bigset.post("/discover")
async def bigset_discover(request: Request):
    if not _l402_ok(request):
        return _challenge("bigset-discover")
    body = await request.json()
    target = body.get("target")
    _spine("bigset_discover", {"target": target})
    # port your real outbound discovery body in here:
    result = {"target": target, "discovered": [], "ts": time.time()}
    return JSONResponse(content=result)
