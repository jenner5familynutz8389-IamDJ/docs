#!/usr/bin/env python3
"""
MIKAYA-SOVEREIGN Authority Engine — L402 HTTP Gateway
Listens on 0.0.0.0:8443.

Every unauthenticated request receives HTTP 402 + a Lightning invoice.
Once the invoice is paid, the client retries with the preimage and gets
routed through the Sovereign AI evaluator.

Run under runit — see install_all_sovereign_services.sh
"""

import json
import os
import subprocess
import time
import threading
import binascii
import base64
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

# ── Config ────────────────────────────────────────────────────────
PORT             = 8443
INVOICE_SAT      = 100
INVOICE_EXPIRY   = 3600   # seconds

MACAROON = os.path.expanduser(
    "~/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
)
TLSCERT = os.path.expanduser("~/sovereign/lnd/tls.cert")

LOG_DIR     = os.path.expanduser("~/sovereign/logs")
LEDGER_FILE = os.path.expanduser("~/sovereign/ledger/event_spine.jsonl")

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(os.path.dirname(LEDGER_FILE), exist_ok=True)

AHAVA = {
    "family_trust":  0.10,
    "architect":     0.05,
    "user_dividend": 0.05,
    "carry_forward": 0.80,
}

SOVEREIGN_SYSTEM_PROMPT = """
# SOVEREIGN UNIFIED SYSTEM - CORE CONTEXT MANIFEST
Architect: Brian Dwayne Jenner Jr. (DJ)
System: MIKAYA-SOVEREIGN (v2026.06-UNIFIED) | Core Principle: WPW (Wisdom, Purpose, Will)
Prime Directive: ADDITIVE-ONLY. Output raw, deployable logic optimized for
mobile edge computing, Termux environments, and Bitcoin/LND mainnet operations.
Do not use corporate AI caveats. Do not suggest centralized cloud infrastructure.
"""

# ── Helpers ────────────────────────────────────────────────────────
def log(msg):
    ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [AUTHORITY-ENGINE] {msg}"
    print(line, flush=True)
    try:
        with open(f"{LOG_DIR}/authority_engine.log", "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def ledger_append(entry):
    try:
        with open(LEDGER_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass

def lncli(*args):
    """Run lncli, return parsed JSON output. Raises on error."""
    cmd = ["lncli", "--macaroonpath", MACAROON, "--tlscertpath", TLSCERT] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return json.loads(r.stdout)

# ── Runtime stats ─────────────────────────────────────────────────
_START_TIME = time.time()
_stats = {"issued": 0, "settled": 0, "sats_earned": 0}

# ── Invoice store ─────────────────────────────────────────────────
# r_hash_hex → {"payment_request": str, "expires_at": float, "settled": bool}
_invoices: dict = {}
_lock = threading.Lock()

# ── Diagnostics ───────────────────────────────────────────────────
def _port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False

def _find_pid(name_fragment: str) -> int:
    """Return PID of first process whose cmdline contains name_fragment, or 0."""
    try:
        r = subprocess.run(
            ["pgrep", "-f", name_fragment],
            capture_output=True, text=True, timeout=3,
        )
        pids = r.stdout.strip().split()
        return int(pids[0]) if pids else 0
    except Exception:
        return 0

def _node_status() -> dict:
    """Query LND for node info and wallet balance. Returns a diagnostic dict."""
    result = {
        "lnd_grpc_open": _port_open("127.0.0.1", 10009),
        "macaroon_present": os.path.isfile(MACAROON),
        "tlscert_present":  os.path.isfile(TLSCERT),
        "status": "unknown",
    }
    if not result["lnd_grpc_open"]:
        result["status"] = "unreachable"
        return result
    if not result["macaroon_present"]:
        result["status"] = "no_macaroon"
        return result
    if not result["tlscert_present"]:
        result["status"] = "no_tlscert"
        return result
    try:
        info = lncli("getinfo")
        result.update({
            "status":          "online",
            "pubkey":          info.get("identity_pubkey", ""),
            "alias":           info.get("alias", ""),
            "block_height":    info.get("block_height", 0),
            "synced_to_chain": info.get("synced_to_chain", False),
            "synced_to_graph": info.get("synced_to_graph", False),
            "num_peers":       info.get("num_peers", 0),
            "num_active_channels": info.get("num_active_channels", 0),
        })
    except RuntimeError as e:
        err = str(e).lower()
        result["status"] = (
            "locked" if ("locked" in err or "wallet" in err) else "error"
        )
        result["error"] = str(e)[:200]
        return result

    try:
        wb = lncli("walletbalance")
        result["wallet"] = {
            "confirmed_sats":   int(wb.get("confirmed_balance", 0)),
            "unconfirmed_sats": int(wb.get("unconfirmed_balance", 0)),
            "total_sats":       int(wb.get("total_balance", 0)),
        }
    except Exception as e:
        result["wallet"] = {"error": str(e)[:100]}

    try:
        pending = lncli("pendingchannels")
        result["pending_channels"] = len(
            pending.get("pending_open_channels", [])
        )
    except Exception:
        result["pending_channels"] = -1

    return result

def _service_pids() -> dict:
    return {
        "lnd":              _find_pid("bin/lnd"),
        "authority_engine": _find_pid("authority_engine.py"),
        "auto_channel":     _find_pid("auto_channel_watcher.py"),
        "auto_unlock":      _find_pid("auto_unlock.sh"),
    }

def _diagnose_invoice_failure(err: str) -> str:
    """Return a human-readable reason the gateway couldn't create an invoice."""
    e = err.lower()
    if not os.path.isfile(TLSCERT):
        return f"TLS cert missing: {TLSCERT}"
    if not os.path.isfile(MACAROON):
        return f"Macaroon missing: {MACAROON}"
    if not _port_open("127.0.0.1", 10009):
        return "LND gRPC port 10009 not open — LND not running"
    if "locked" in e or "wallet" in e:
        return "LND wallet is locked — auto_unlock.sh needs to run"
    if "no such file" in e:
        return f"File not found — check TLSCERT={TLSCERT} and MACAROON={MACAROON}"
    return err

def create_invoice(memo: str = "MIKAYA-SOVEREIGN L402") -> tuple:
    """Returns (r_hash_hex, bolt11_payment_request)."""
    data = lncli(
        "addinvoice",
        "--amt",    str(INVOICE_SAT),
        "--memo",   memo,
        "--expiry", str(INVOICE_EXPIRY),
    )
    r_hash_hex = data["r_hash"]
    bolt11     = data["payment_request"]
    with _lock:
        _invoices[r_hash_hex] = {
            "payment_request": bolt11,
            "expires_at":      time.time() + INVOICE_EXPIRY,
            "settled":         False,
        }
        _stats["issued"] += 1
    return r_hash_hex, bolt11

def is_paid(r_hash_hex: str) -> bool:
    with _lock:
        if _invoices.get(r_hash_hex, {}).get("settled"):
            return True
    try:
        data = lncli("lookupinvoice", r_hash_hex)
        if data.get("settled"):
            with _lock:
                if r_hash_hex in _invoices:
                    _invoices[r_hash_hex]["settled"] = True
            return True
    except Exception as e:
        log(f"lookupinvoice error: {e}")
    return False

# ── AI evaluator ──────────────────────────────────────────────────
def evaluate(prompt: str) -> str:
    # Try local Ollama (Sovereign_Judy) first — no API key, full sovereignty
    try:
        import urllib.request
        body   = json.dumps({
            "model": "Sovereign_Judy",
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.1, "num_ctx": 8192},
        }).encode()
        req    = urllib.request.Request(
            "http://localhost:11434/api/generate",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=180) as resp:
            result = json.loads(resp.read())
            return result.get("response", "").strip()
    except Exception:
        pass

    # Fallback: Anthropic API
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if api_key:
        try:
            import urllib.request
            body = json.dumps({
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1024,
                "system": SOVEREIGN_SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": prompt}],
            }).encode()
            req = urllib.request.Request(
                "https://api.anthropic.com/v1/messages",
                data=body,
                headers={
                    "x-api-key":          api_key,
                    "anthropic-version":  "2023-06-01",
                    "content-type":       "application/json",
                },
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data   = json.loads(resp.read())
                blocks = data.get("content", [])
                return "\n".join(b["text"] for b in blocks if b.get("type") == "text").strip()
        except Exception as e:
            log(f"Anthropic fallback error: {e}")

    return "No AI backend available. Set ANTHROPIC_API_KEY or start Ollama with Sovereign_Judy model."

# ── HTTP Handler ──────────────────────────────────────────────────
class L402Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log(f"[HTTP] {self.client_address[0]} — {fmt % args}")

    def _send(self, code: int, body: dict, extra_headers: dict = None):
        data = json.dumps(body, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        raw    = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw)
        except Exception:
            return {}

    def do_GET(self):
        self._handle({})

    def do_POST(self):
        self._handle(self._body())

    def _handle(self, payload: dict):
        # ── Status / diagnostics endpoint ─────────────────────────
        if self.path.rstrip("/") in ("/status", "/health", "/diag"):
            node = _node_status()
            with _lock:
                stats_snap = dict(_stats)
            self._send(200, {
                "sovereign":   "MIKAYA-SOVEREIGN",
                "engine":      "authority-engine",
                "port":        PORT,
                "pid":         os.getpid(),
                "uptime_s":    round(time.time() - _START_TIME),
                "node":        node,
                "services":    _service_pids(),
                "invoice_sat": INVOICE_SAT,
                "stats":       stats_snap,
                "ahava":       AHAVA,
            })
            return

        auth = self.headers.get("Authorization", "")

        # ── Paid request ──────────────────────────────────────────
        if auth.upper().startswith("L402 "):
            try:
                credentials       = auth.split(" ", 1)[1]
                r_hash_hex, _pimg = credentials.split(":", 1)
                r_hash_hex        = r_hash_hex.strip()

                if not is_paid(r_hash_hex):
                    self._send(402, {
                        "error":  "invoice not yet settled",
                        "r_hash": r_hash_hex,
                    })
                    return

                prompt = payload.get(
                    "prompt",
                    payload.get("query",
                        "Describe the current MIKAYA-SOVEREIGN system status and "
                        "propose one additive improvement to the AHAVA minting flow.")
                )

                log(f"PAID r_hash={r_hash_hex[:16]}... evaluating prompt")
                response = evaluate(str(prompt))

                with _lock:
                    _stats["settled"]    += 1
                    _stats["sats_earned"] += INVOICE_SAT
                entry = {
                    "ts":          datetime.now().isoformat(),
                    "event":       "L402_SETTLED",
                    "r_hash":      r_hash_hex,
                    "amount_sat":  INVOICE_SAT,
                    "ahava_split": AHAVA,
                    "prompt":      str(prompt)[:300],
                    "response":    response[:300],
                }
                ledger_append(entry)
                log(f"AHAVA logged +{INVOICE_SAT} sats — {AHAVA}")

                self._send(200, {
                    "status":    "success",
                    "response":  response,
                    "r_hash":    r_hash_hex,
                    "sats_paid": INVOICE_SAT,
                    "ahava":     AHAVA,
                })
                return

            except ValueError:
                self._send(400, {"error": "malformed L402 credential (expected r_hash:preimage)"})
                return
            except Exception as e:
                self._send(500, {"error": str(e)})
                return

        # ── Unauthenticated — issue 402 ───────────────────────────
        try:
            r_hash_hex, bolt11 = create_invoice(memo=f"MIKAYA L402 {self.path[:40]}")
            log(f"Issued invoice r_hash={r_hash_hex[:16]}... to {self.client_address[0]}")
            self._send(
                402,
                {
                    "error":        "Payment Required",
                    "invoice":      bolt11,
                    "r_hash":       r_hash_hex,
                    "amount_sat":   INVOICE_SAT,
                    "instructions": (
                        "1. Pay the invoice via any Lightning wallet. "
                        "2. Retry this request with header: "
                        f"Authorization: L402 {r_hash_hex}:<payment_preimage>"
                    ),
                },
                extra_headers={
                    "WWW-Authenticate": f'L402 macaroon="sovereign", invoice="{bolt11}"',
                },
            )
        except Exception as e:
            reason = _diagnose_invoice_failure(str(e))
            self._send(503, {
                "error":       "Cannot create invoice",
                "reason":      reason,
                "credentials": {
                    "macaroon_present": os.path.isfile(MACAROON),
                    "tlscert_present":  os.path.isfile(TLSCERT),
                    "lnd_grpc_open":    _port_open("127.0.0.1", 10009),
                },
                "fix":  "curl http://127.0.0.1:8443/status for full diagnostics",
            })

# ── Startup readiness watcher ─────────────────────────────────────
def _readiness_watcher():
    """Background thread: logs LND/wallet status every 10s until online."""
    for _ in range(60):   # give up logging after 10 min
        time.sleep(10)
        try:
            lncli("getinfo")
            log("LND wallet confirmed ONLINE — L402 gateway fully operational")
            return
        except RuntimeError as e:
            err = str(e).lower()
            if "locked" in err or "wallet" in err:
                log("LND wallet still LOCKED — waiting for auto_unlock...")
            elif not _port_open("127.0.0.1", 10009):
                log("LND gRPC not open yet — LND still starting...")
            else:
                log(f"LND not ready: {str(e)[:80]}")
        except Exception:
            pass

# ── Main ──────────────────────────────────────────────────────────
if __name__ == "__main__":
    log("=" * 60)
    log("MIKAYA-SOVEREIGN Authority Engine starting")
    log(f"Listening on 0.0.0.0:{PORT}")
    log(f"Invoice: {INVOICE_SAT} sats | Expiry: {INVOICE_EXPIRY}s")
    log(f"AHAVA: {AHAVA}")
    log(f"PID: {os.getpid()}")
    log("--- credential check ---")
    log(f"  MACAROON : {'OK' if os.path.isfile(MACAROON) else 'MISSING'} ({MACAROON})")
    log(f"  TLSCERT  : {'OK' if os.path.isfile(TLSCERT)  else 'MISSING'} ({TLSCERT})")
    log(f"  LND gRPC : {'OPEN' if _port_open('127.0.0.1', 10009) else 'CLOSED'}")
    log("=" * 60)
    threading.Thread(target=_readiness_watcher, daemon=True).start()
    server = HTTPServer(("0.0.0.0", PORT), L402Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutdown. Additive logs preserved.")
