#!/usr/bin/env python3
"""
MIKAYA-SOVEREIGN Auto Channel Watcher

Watches on-chain balance every 60s via lncli.
The moment confirmed balance >= OPEN_THRESHOLD_SATS and no channel exists,
it automatically:
  1. Connects to ACINQ (best-connected peer for receiving payments)
  2. Opens a channel with CHANNEL_SAT local balance
  3. Logs the funding txid to the sovereign ledger

No human action required after funds land on-chain.
Run under runit — see install_all_sovereign_services.sh
"""

import json
import os
import subprocess
import time
from datetime import datetime

# ── Config ────────────────────────────────────────────────────────
OPEN_THRESHOLD_SATS = 50_000   # minimum confirmed on-chain to attempt open
CHANNEL_SAT         = 40_000   # channel local amount (leave ~10k for fees)
POLL_INTERVAL       = 60       # seconds between balance checks

MACAROON = os.path.expanduser(
    "~/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
)
TLSCERT = os.path.expanduser("~/.lnd/tls.cert")

LOG_DIR     = os.path.expanduser("~/sovereign/logs")
LEDGER_FILE = os.path.expanduser("~/sovereign/ledger/event_spine.jsonl")

# ACINQ — Lightning Labs' Phoenix backend, extremely well-connected
# Good first peer: routes inbound payments reliably
PEER_PUBKEY = "03864ef025fde8fb587d989186ce6a4a186895ee44a926bfc370e2c366597a3f8f"
PEER_HOST   = "3.33.236.230:9735"

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(os.path.dirname(LEDGER_FILE), exist_ok=True)

# ── Helpers ────────────────────────────────────────────────────────
def log(msg):
    ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [AUTO-CHANNEL] {msg}"
    print(line, flush=True)
    try:
        with open(f"{LOG_DIR}/auto_channel.log", "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def ledger_append(entry):
    try:
        with open(LEDGER_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass

def lncli(*args, timeout=60):
    cmd = ["lncli", "--macaroonpath", MACAROON, "--tlscertpath", TLSCERT] + list(args)
    r   = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return json.loads(r.stdout) if r.stdout.strip() else {}

# ── LND queries ───────────────────────────────────────────────────
def wallet_balance() -> int:
    """Returns confirmed on-chain balance in sats, or -1 if unavailable."""
    try:
        data = lncli("walletbalance")
        return int(data.get("confirmed_balance", 0))
    except Exception as e:
        log(f"walletbalance failed: {e}")
        return -1

def channel_count() -> int:
    """Returns total open + pending channel count."""
    total = 0
    try:
        data   = lncli("listchannels")
        total += len(data.get("channels", []))
    except Exception:
        pass
    try:
        data   = lncli("pendingchannels")
        total += len(data.get("pending_open_channels", []))
    except Exception:
        pass
    return total

def connect_peer() -> bool:
    try:
        lncli("connect", f"{PEER_PUBKEY}@{PEER_HOST}", timeout=30)
        return True
    except RuntimeError as e:
        if "already connected" in str(e).lower():
            return True
        log(f"connect failed: {e}")
        return False

def open_channel() -> dict:
    return lncli(
        "openchannel",
        "--node_key",    PEER_PUBKEY,
        "--local_amt",   str(CHANNEL_SAT),
        "--conf_target", "6",
        timeout=90,
    )

# ── Main loop ─────────────────────────────────────────────────────
def run():
    log("Auto Channel Watcher starting")
    log(f"Threshold: {OPEN_THRESHOLD_SATS:,} sats → open {CHANNEL_SAT:,} sat channel to ACINQ")
    channel_opened = False

    while True:
        try:
            if not channel_opened and channel_count() > 0:
                log("Channel(s) already exist — monitoring only")
                channel_opened = True

            bal = wallet_balance()

            if bal < 0:
                log("LND not ready or wallet locked — waiting")
                time.sleep(POLL_INTERVAL)
                continue

            log(f"On-chain confirmed: {bal:,} sats | channels: {channel_count()}")

            if not channel_opened and bal >= OPEN_THRESHOLD_SATS:
                log(f"Threshold reached ({bal:,} sats). Connecting to ACINQ...")
                ledger_append({
                    "ts":      datetime.now().isoformat(),
                    "event":   "AUTO_CHANNEL_TRIGGERED",
                    "balance": bal,
                    "peer":    PEER_PUBKEY,
                    "channel_sat": CHANNEL_SAT,
                })

                if connect_peer():
                    log("Peer connected. Opening channel...")
                    try:
                        result = open_channel()
                        txid   = result.get("funding_txid", result.get("funding_txid_str", ""))
                        log(f"Channel open submitted. Funding txid: {txid}")
                        log("Waiting ~6 blocks (~1 hour) for confirmation.")
                        ledger_append({
                            "ts":          datetime.now().isoformat(),
                            "event":       "CHANNEL_OPEN_SUBMITTED",
                            "funding_txid": txid,
                            "local_sat":   CHANNEL_SAT,
                            "peer":        PEER_PUBKEY,
                        })
                        channel_opened = True
                    except RuntimeError as e:
                        log(f"openchannel error: {e}. Will retry next cycle.")
                else:
                    log("Peer connection failed. Will retry next cycle.")

        except Exception as e:
            log(f"Watcher error: {e}")

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    run()
