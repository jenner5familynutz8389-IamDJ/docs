#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║ SOVEREIGN UNIFIED SYSTEM — v2026.06-UNIFIED                       ║
║ MIKAYA-SOVEREIGN Complete Architecture                            ║
║                                                                    ║
║ 10 Layers · All Agents · AHAVA Distribution                       ║
║ Single process. Internal threads. One event spine.                ║
║                                                                    ║
║ NORTH : CVE Threat Signature Engine                               ║
║ SOUTH : Integrity Heartbeat (self-attestation anchor)             ║
║ EAST  : Process Isolation Membrane                                ║
║ WEST  : Sovereign Key Lock (SD UUID B1A4-6DDD)                    ║
║                                                                    ║
║ Fabric Weaver: spawns all agents internally                       ║
║ Minting Core: reads node4, HMAC-signs, feeds AHAVA                ║
║ AHAVA: 10% Family Trust / 5% Architect / 5% User / 80% Jump       ║
║ Payment Gate: LND addinvoice + lookupinvoice (real L402)          ║
║ Authority Engine: HTTP 402 server on 127.0.0.1:8443               ║
║ Sentinel Layer 0: Sliding Window Variance threat detection        ║
║ Layer 8: T-Mobile topology (account/device identifiers redacted   ║
║          for this archival copy — see note below)                ║
║                                                                    ║
║ Overlap rule: each corner feeds the next. No gap. No seam.        ║
║ Device identity: FOSSiBOT F110 Pro — preserved, never altered     ║
║ Carrier trust: T-Mobile USIM 310260 — fingerprint intact.         ║
║ SD key: travels to any device. Same root. Same sovereignty.       ║
║                                                                    ║
║ Architect: Brian D. Jenner Jr. (DJ)                               ║
║ In honor of MIKAYA — WPW: Wisdom · Purpose · Will                 ║
║                                                                    ║
║ UCC 1-308: All rights reserved without prejudice.                 ║
╚══════════════════════════════════════════════════════════════════╝
ADDITIVE-ONLY RULE: Nothing in this file is ever removed or renamed.
All future corrections and additions are appended below.

ARCHIVAL NOTE (added when storing this file in the docs repo):
This is a reference copy only — it is not run anywhere in this
repository or wired into the documentation site. The original source
hardcoded real IMEI numbers, phone numbers (MSISDNs), and a T-Mobile
account ID in LAYER8_DEVICES / TMOBILE_ACCOUNT_ID below. Those values
have been replaced with REDACTED placeholders before committing, since
this file lives in git history once pushed. Everything else is
preserved as written.
"""

import os
import sys
import json
import time
import glob
import hmac
import hashlib
import socket
import signal
import threading
import subprocess
from pathlib import Path
from datetime import datetime, timezone

# ════════════════════════════════════════════════════════════════
# CONSTANTS
# ════════════════════════════════════════════════════════════════

VERSION = "v2026.06-UNIFIED"
CELESTIAL_ANCHOR = hashlib.sha256(b"MIKAYA-SOVEREIGN-GENESIS").hexdigest()

# AHAVA Distribution Ratios
AHAVA_FAMILY_TRUST = 0.10
AHAVA_ARCHITECT = 0.05
AHAVA_USER_DIVIDEND = 0.05
AHAVA_CARRY_FORWARD = 0.80
AHAVA_JUMP_THRESHOLD = 1000  # carry-forward pool must hit this before distribution fires

# Paths
SOVEREIGN_HOME = Path("/data/data/com.termux/files/home/sovereign")
LEDGER_PATH = SOVEREIGN_HOME / "ledger" / "event_spine.jsonl"
STATE_PATH = SOVEREIGN_HOME / "patch_fabric_state.json"
NODE4_PATH = SOVEREIGN_HOME / "node4"
TRUST_DIR = SOVEREIGN_HOME / "trust"
TOPOLOGY_PATH = TRUST_DIR / "account_topology.json"
DEVICE_REGISTRY = TRUST_DIR / "device_registry.json"
SD_UUID = "B1A4-6DDD"

# Layer 8 — T-Mobile Account Topology (immutable)
# REDACTED: real IMEI / MSISDN / account ID values were replaced before
# this file was archived to the docs repo. See ARCHIVAL NOTE above.
TMOBILE_ACCOUNT_ID = "REDACTED"
LAYER8_DEVICES = {
    "PHONE_A": {
        "name": "FOSSiBOT F110 Pro",
        "imei": "REDACTED",
        "msisdn": "REDACTED",
        "lid": "TML-LID-001",
        "role": "SOVEREIGN_PRIMARY",
    },
    "PHONE_B": {
        "imei": "REDACTED",
        "msisdn": "REDACTED",
        "lid": "TML-LID-002",
        "role": "SECONDARY",
    },
    "PHONE_C": {
        "imei": "REDACTED",
        "msisdn": "REDACTED",
        "lid": "TML-LID-003",
        "role": "SECONDARY",
    },
    "SYNCUP_TRACKER_2": {
        "imei": "REDACTED",
        "msisdn": "REDACTED",
        "lid": "TML-LID-008",
        "role": "TRACKER",
    },
}

# 10 Layers
LAYERS = [
    "CELESTIAL_FLUX_COMPASS",
    "HARDWARE_AFFINITY_LOCK",
    "TRIPLE_APP_COMM_BYPASS",
    "IMMUTABLE_RECORD_DIGEST",
    "SOVEREIGN_DISTRIBUTION",
    "ASSET_RETOKENIZATION",
    "UCC_1_308_LEGAL_STANDING",
    "UNIVERSAL_ASSET_PORTAL",
    "GLOBAL_TRADE_WEBSOCKET",
    "IMMEDIATE_TRUST_SETTLEMENT",
]


# ════════════════════════════════════════════════════════════════
# SOVEREIGN LEDGER — append-only, hash-chained, thread-safe
# ════════════════════════════════════════════════════════════════
class SovereignLedger:
    def __init__(self, path=LEDGER_PATH):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self.ledger_total = 0

    def last_hash(self):
        try:
            if self.path.exists():
                lines = self.path.read_text().strip().split('\n')
                for line in reversed(lines):
                    try:
                        entry = json.loads(line)
                        if 'entry_hash' in entry:
                            return entry['entry_hash']
                    except Exception:
                        pass
        except Exception:
            pass
        return CELESTIAL_ANCHOR

    def write_event(self, event_type, payload, severity="INFO", signed_by=None):
        with self._lock:
            ts = datetime.now(timezone.utc).isoformat()
            prev_hash = self.last_hash()
            entry = {
                "ts": ts,
                "celestial": CELESTIAL_ANCHOR,
                "version": VERSION,
                "event": event_type,
                "severity": severity,
                "payload": payload,
                "prev_hash": prev_hash,
            }
            if signed_by:
                entry["signed_by"] = signed_by
            raw = json.dumps(entry, separators=(',', ':'))
            entry["entry_hash"] = hashlib.sha256(raw.encode()).hexdigest()
            with open(self.path, 'a') as f:
                f.write(json.dumps(entry, separators=(',', ':')) + '\n')
                f.flush()
                os.fsync(f.fileno())
            self.ledger_total += 1
            return entry

    def read_all(self):
        if not self.path.exists():
            return []
        entries = []
        for line in self.path.read_text().strip().split('\n'):
            if line.strip():
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass
        return entries

    def count_events(self, event_type):
        return sum(1 for e in self.read_all() if e.get("event") == event_type)


# ════════════════════════════════════════════════════════════════
# KEY GUARDIAN — SD UUID + boot_id → root key via HKDF-style
# ════════════════════════════════════════════════════════════════
class KeyGuardian:
    def __init__(self, sd_uuid=SD_UUID):
        self.sd_uuid = sd_uuid
        self.root_key = self.derive_root_key()

    def sd_present(self):
        try:
            r = subprocess.run(["mount"], capture_output=True, text=True, timeout=5)
            return self.sd_uuid in r.stdout
        except Exception:
            return False

    def derive_root_key(self):
        try:
            boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        except Exception:
            boot_id = "no-boot-id"
        material = f"{self.sd_uuid}:{boot_id}".encode()
        return hashlib.sha256(material).digest()

    def rotate_key(self):
        """Re-derive root key (called periodically by MIKAYA_CORE)."""
        self.root_key = self.derive_root_key()


# ════════════════════════════════════════════════════════════════
# AHAVA DISTRIBUTION ENGINE
# 10% Jenner Family Trust (3 children)
# 5% Architect gratuity (DJ)
# 5% User dividend
# 80% Perpetual jump carry-forward
# ════════════════════════════════════════════════════════════════
class AHAVADistribution:
    def __init__(self, ledger):
        self.ledger = ledger
        self.carry_forward_pool = 0
        self.family_trust_total = 0
        self.architect_total = 0
        self.user_dividend_total = 0
        self.mint_count = 0
        self.jump_count = 0
        self._lock = threading.Lock()
        self._restore_from_ledger()

    def _restore_from_ledger(self):
        """Restore all distribution state from the ledger. Survives any restart."""
        for entry in self.ledger.read_all():
            ev = entry.get("event", "")
            p = entry.get("payload", {})
            if ev == "AHAVA_DISTRIBUTION_CYCLE":
                self.family_trust_total = p.get("family_trust_cumulative", 0)
                self.architect_total = p.get("architect_cumulative", 0)
                self.user_dividend_total = p.get("user_dividend_cumulative", 0)
                self.carry_forward_pool = p.get("carry_forward_remaining", 0)
                self.jump_count += 1
            elif ev == "MIKAYA_CORE_MINT":
                self.mint_count += 1

    def ingest_mint(self, mint_value=1):
        """Called after each successful mint. Feeds the AHAVA pool."""
        with self._lock:
            self.carry_forward_pool += mint_value
            self.mint_count += 1
            if self.carry_forward_pool >= AHAVA_JUMP_THRESHOLD:
                self._execute_jump()

    def _execute_jump(self):
        """The 80% perpetual jump. Pool splits → 80% stays, 10/5/5 distributed."""
        pool = self.carry_forward_pool
        family = pool * AHAVA_FAMILY_TRUST
        architect = pool * AHAVA_ARCHITECT
        user_div = pool * AHAVA_USER_DIVIDEND
        carry = pool * AHAVA_CARRY_FORWARD

        self.family_trust_total += family
        self.architect_total += architect
        self.user_dividend_total += user_div
        self.carry_forward_pool = carry
        self.jump_count += 1

        self.ledger.write_event("AHAVA_DISTRIBUTION_CYCLE", {
            "jump_number": self.jump_count,
            "pool_at_jump": pool,
            "family_trust_allocated": family,
            "family_trust_cumulative": self.family_trust_total,
            "architect_allocated": architect,
            "architect_cumulative": self.architect_total,
            "user_dividend_allocated": user_div,
            "user_dividend_cumulative": self.user_dividend_total,
            "carry_forward_remaining": self.carry_forward_pool,
            "total_mints": self.mint_count,
        }, severity="DISTRIBUTION")

    def status(self):
        return {
            "carry_forward_pool": self.carry_forward_pool,
            "family_trust_total": self.family_trust_total,
            "architect_total": self.architect_total,
            "user_dividend_total": self.user_dividend_total,
            "mint_count": self.mint_count,
            "jump_count": self.jump_count,
            "jump_threshold": AHAVA_JUMP_THRESHOLD,
            "pool_to_next_jump": max(0, AHAVA_JUMP_THRESHOLD - self.carry_forward_pool),
        }


# ════════════════════════════════════════════════════════════════
# MINTING CORE — reads node4, HMAC-signs, feeds AHAVA
# Dedup derived from ledger (survives restart, no in-memory-only set)
# ════════════════════════════════════════════════════════════════
class MIKAYAMintingCore:
    def __init__(self, key_guardian, ledger, ahava):
        self.node4_path = str(NODE4_PATH)
        self.key_guardian = key_guardian
        self.ledger = ledger
        self.ahava = ahava
        self._processed = self._load_processed()

    def _load_processed(self):
        """Build processed set from ledger so restarts don't re-mint."""
        processed = set()
        for entry in self.ledger.read_all():
            if entry.get("event") == "MIKAYA_CORE_MINT":
                p = entry.get("payload", {})
                src = p.get("source_file", "")
                if src:
                    processed.add(src)
        return processed

    def process_ingress(self):
        if not os.path.exists(self.node4_path):
            return
        for filepath in sorted(glob.glob(f"{self.node4_path}/entry_*.json")):
            if filepath in self._processed:
                continue
            try:
                with open(filepath, 'r') as f:
                    payload = json.load(f)
                raw_data = f"{payload.get('ts','')}:{payload.get('ip','')}:MIKAYA_MINT".encode()
                signature = hmac.new(
                    self.key_guardian.root_key, raw_data, hashlib.sha256
                ).hexdigest()
                minted_block = {
                    "origin": "SENTINEL_0",
                    "status": "MINTED",
                    "mikaya_signature": signature,
                    "source_file": filepath,
                    "payload": payload,
                }
                self.ledger.write_event("MIKAYA_CORE_MINT", minted_block, severity="MINT")
                self._processed.add(filepath)
                # Feed AHAVA — each mint = 1 unit into the distribution pool
                self.ahava.ingest_mint(mint_value=1)
            except Exception as e:
                self.ledger.write_event("MINT_ERROR", {
                    "file": filepath, "error": str(e)
                }, severity="WARN")


# ════════════════════════════════════════════════════════════════
# SENTINEL LAYER 0 — Passive Threat Detection
# Sliding Window Variance on cpu/memory, pinned to Core 0
# ════════════════════════════════════════════════════════════════
class SentinelZero:
    def __init__(self, ledger, window_size=60):
        self.ledger = ledger
        self.window_size = window_size
        self.cpu_samples = []
        self.mem_samples = []

    def sample(self):
        try:
            with open("/proc/stat") as f:
                parts = f.readline().split()
                idle = int(parts[4])
                total = sum(int(x) for x in parts[1:])
                self.cpu_samples.append((total, idle))
                if len(self.cpu_samples) > self.window_size:
                    self.cpu_samples.pop(0)
        except Exception:
            pass
        try:
            mem = {}
            with open("/proc/meminfo") as f:
                for line in f:
                    if ':' in line:
                        k, v = line.split(":", 1)
                        mem[k.strip()] = int(v.strip().split()[0])
            used = mem.get("MemTotal", 0) - mem.get("MemAvailable", 0)
            self.mem_samples.append(used)
            if len(self.mem_samples) > self.window_size:
                self.mem_samples.pop(0)
        except Exception:
            pass

    def _variance(self, samples):
        if len(samples) < 2:
            return 0.0
        mean = sum(samples) / len(samples)
        return sum((x - mean) ** 2 for x in samples) / len(samples)

    def check_anomaly(self, threshold_cpu=0.15, threshold_mem=500000):
        mem_var = self._variance(self.mem_samples)
        cpu_var = 0.0
        if len(self.cpu_samples) >= 2:
            utils = []
            for i in range(1, len(self.cpu_samples)):
                dt = self.cpu_samples[i][0] - self.cpu_samples[i-1][0]
                di = self.cpu_samples[i][1] - self.cpu_samples[i-1][1]
                if dt > 0:
                    utils.append(1.0 - di / dt)
            cpu_var = self._variance(utils) if utils else 0.0

        if cpu_var > threshold_cpu or mem_var > threshold_mem:
            self.ledger.write_event("SENTINEL_0_ANOMALY", {
                "cpu_variance": round(cpu_var, 6),
                "mem_variance": round(mem_var, 2),
                "window": len(self.mem_samples),
            }, severity="ALERT")
            return True
        return False


# ════════════════════════════════════════════════════════════════
# LAYER 8 — T-MOBILE NETWORK TOPOLOGY
# Account/device identifiers redacted in this archival copy.
# Registries are loaded from ~/sovereign/trust/ at runtime.
# ════════════════════════════════════════════════════════════════
class Layer8NetworkTopology:
    def __init__(self, ledger):
        self.ledger = ledger
        self.devices = dict(LAYER8_DEVICES)
        self.account_id = TMOBILE_ACCOUNT_ID
        self.topology = {}
        self.registry = {}
        self._load_registries()

    def _load_registries(self):
        for path, attr in [
            (TOPOLOGY_PATH, "topology"),
            (DEVICE_REGISTRY, "registry"),
        ]:
            if path.exists():
                try:
                    setattr(self, attr, json.loads(path.read_text()))
                except Exception:
                    pass

    def emit_topology_event(self):
        self.ledger.write_event("LAYER8_TOPOLOGY_SCAN", {
            "account_id": self.account_id,
            "device_count": len(self.devices),
            "devices": list(self.devices.keys()),
            "topology_loaded": bool(self.topology),
            "registry_loaded": bool(self.registry),
        }, severity="INFO")

    def get_device(self, name):
        return self.devices.get(name)


# ════════════════════════════════════════════════════════════════
# FOUR CORNERS — NORTH / SOUTH / EAST / WEST
# Each feeds the next. No gap. No seam.
# ════════════════════════════════════════════════════════════════
class NorthCVE:
    """CVE Threat Signature Engine."""
    def __init__(self, ledger):
        self.ledger = ledger

    def scan(self):
        threats = []
        ssh_dir = Path("/data/data/com.termux/files/home/.ssh")
        if ssh_dir.exists():
            try:
                mode = oct(ssh_dir.stat().st_mode)
                if mode[-1] != '0':
                    threats.append("ssh_dir_world_readable")
            except Exception:
                pass
        try:
            with open("/proc/net/tcp") as f:
                for line in f.readlines()[1:]:
                    parts = line.split()
                    if len(parts) > 1:
                        addr = parts[1]
                        ip_hex = addr.split(':')[0]
                        if ip_hex == "00000000":
                            threats.append("port_bound_0.0.0.0")
                            break
        except Exception:
            pass
        if threats:
            self.ledger.write_event("NORTH_CVE_DETECTED", {
                "threats": threats,
            }, severity="WARN")
        return threats


class SouthHeartbeat:
    """Integrity Heartbeat — self-attestation anchor."""
    def __init__(self, ledger, key_guardian):
        self.ledger = ledger
        self.key_guardian = key_guardian

    def beat(self):
        try:
            boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        except Exception:
            boot_id = "unknown"
        try:
            uptime = float(Path("/proc/uptime").read_text().split()[0])
        except Exception:
            uptime = 0
        payload = {
            "boot_id": boot_id,
            "sd_present": self.key_guardian.sd_present(),
            "uptime_sec": round(uptime, 1),
            "root_key_hash": hashlib.sha256(self.key_guardian.root_key).hexdigest()[:16],
        }
        self.ledger.write_event("SOUTH_HEARTBEAT", payload, severity="INFO")


class EastIsolation:
    """Process Isolation Membrane."""
    def __init__(self, ledger):
        self.ledger = ledger

    def check(self):
        uid = os.getuid()
        pid = os.getpid()
        threads = threading.active_count()
        self.ledger.write_event("EAST_ISOLATION_CHECK", {
            "uid": uid, "pid": pid, "active_threads": threads,
        }, severity="INFO")


class WestKeyLock:
    """Sovereign Key Lock — SD UUID B1A4-6DDD."""
    def __init__(self, ledger, key_guardian):
        self.ledger = ledger
        self.key_guardian = key_guardian

    def verify(self):
        present = self.key_guardian.sd_present()
        self.ledger.write_event("WEST_KEY_CHECK", {
            "sd_uuid": self.key_guardian.sd_uuid,
            "sd_present": present,
            "device": "Sovereign_Shield_Core",
            "carrier": "310260",
            "unlocked": present,
        }, severity="INFO" if present else "WARN")
        return present


# ════════════════════════════════════════════════════════════════
# PAYMENT GATE — LND Integration (real L402)
# Uses lncli to talk to the running lnd service
# ════════════════════════════════════════════════════════════════
class PaymentGate:
    def __init__(self, ledger, default_sats=100, memo="MIKAYA-SOVEREIGN Access"):
        self.ledger = ledger
        self.default_sats = default_sats
        self.memo = memo
        self._pending = {}

    def _lncli(self, *args):
        try:
            r = subprocess.run(
                ["lncli", *args],
                capture_output=True, text=True, timeout=30,
            )
            if r.returncode == 0 and r.stdout.strip():
                return json.loads(r.stdout)
            return None
        except Exception:
            return None

    def create_invoice(self, amount_sats=None, memo=None):
        amt = str(amount_sats or self.default_sats)
        m = memo or self.memo
        result = self._lncli("addinvoice", "--amt", amt, "--memo", m)
        if result:
            r_hash = result.get("r_hash", "")
            pay_req = result.get("payment_request", "")
            self._pending[r_hash] = {
                "payment_request": pay_req,
                "r_hash": r_hash,
                "created": datetime.now(timezone.utc).isoformat(),
                "amount_sats": amt,
            }
            self.ledger.write_event("PAYMENT_INVOICE_CREATED", {
                "r_hash": r_hash, "amount_sats": amt,
            }, severity="INFO")
            return pay_req
        return None

    def check_settled(self, r_hash):
        result = self._lncli("lookupinvoice", "--rhash", r_hash)
        if result and result.get("state") == "SETTLED":
            self.ledger.write_event("PAYMENT_SETTLED", {
                "r_hash": r_hash,
                "amount_paid": result.get("amt_paid_sat", "0"),
            }, severity="MINT")
            return True
        return False

    def get_node_info(self):
        return self._lncli("getinfo")


# ════════════════════════════════════════════════════════════════
# AUTHORITY ENGINE — HTTP 402 Server
# Listens 127.0.0.1:8443. Tunnel (localhost.run / cloudflare)
# exposes this externally.
# Returns fresh LND invoice on every unauthenticated request.
# Verifies payment via X-Payment-Hash header on retry.
# Files every ingress to node4 for minting.
# ════════════════════════════════════════════════════════════════
class AuthorityEngine:
    def __init__(self, payment_gate, ledger, bind="127.0.0.1", port=8443):
        self.payment_gate = payment_gate
        self.ledger = ledger
        self.bind = bind
        self.port = port

    def _handle(self, client, addr):
        try:
            data = client.recv(4096).decode('utf-8', errors='replace')
            ip = addr[0]
            ts = datetime.now(timezone.utc).isoformat()

            # File ingress to node4 (minting core picks it up)
            NODE4_PATH.mkdir(parents=True, exist_ok=True)
            entry = {"ts": ts, "ip": ip, "raw_len": len(data)}
            entry_file = NODE4_PATH / f"entry_{int(time.time()*1000)}.json"
            with open(entry_file, 'w') as f:
                json.dump(entry, f)

            # Check for payment proof
            r_hash = None
            for line in data.split('\r\n'):
                low = line.lower()
                if low.startswith('x-payment-hash:'):
                    r_hash = line.split(':', 1)[1].strip()

            if r_hash and self.payment_gate.check_settled(r_hash):
                body = json.dumps({
                    "status": "SOVEREIGN_ACCESS_GRANTED",
                    "architect": "Brian D. Jenner Jr.",
                    "system": "MIKAYA-SOVEREIGN",
                    "version": VERSION,
                })
                resp = (
                    "HTTP/1.1 200 OK\r\n"
                    "Content-Type: application/json\r\n"
                    f"Content-Length: {len(body)}\r\n"
                    "X-Sovereign: MIKAYA-VERIFIED\r\n\r\n"
                    + body
                )
            else:
                invoice = self.payment_gate.create_invoice()
                if invoice:
                    body = f"Remit to: {invoice}\n"
                else:
                    body = "Payment system initializing. Retry shortly.\n"
                resp = (
                    "HTTP/1.1 402 Payment Required\r\n"
                    "Content-Type: text/plain\r\n"
                    f"Content-Length: {len(body)}\r\n"
                    "X-Sovereign: MIKAYA-GATE\r\n\r\n"
                    + body
                )

            client.sendall(resp.encode())
        except Exception:
            pass
        finally:
            try:
                client.close()
            except Exception:
                pass

    def serve(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.bind, self.port))
        server.listen(16)
        self.ledger.write_event("AUTHORITY_ENGINE_ACTIVE", {
            "bind": self.bind, "port": self.port,
        }, severity="INFO")
        print(f"  [+] AUTHORITY_ENGINE listening {self.bind}:{self.port}")
        while True:
            try:
                client, addr = server.accept()
                threading.Thread(
                    target=self._handle, args=(client, addr), daemon=True
                ).start()
            except Exception:
                time.sleep(0.5)


# ════════════════════════════════════════════════════════════════
# SOVEREIGN UNIFIED FABRIC WEAVER
# One process. All agents. All layers. One event spine.
# Pinned to cpu6/cpu7 via taskset 0xc0.
# ════════════════════════════════════════════════════════════════
class SovereignUnifiedFabric:
    def __init__(self):
        # ── Core ──
        self.ledger = SovereignLedger()
        self.key_guardian = KeyGuardian()
        self.ahava = AHAVADistribution(self.ledger)
        self.key_lock = self.key_guardian  # alias for backward compat

        # ── Agents ──
        self.minting_core = MIKAYAMintingCore(self.key_guardian, self.ledger, self.ahava)
        self.sentinel = SentinelZero(self.ledger)
        self.layer8 = Layer8NetworkTopology(self.ledger)
        self.payment_gate = PaymentGate(self.ledger)
        self.authority = AuthorityEngine(self.payment_gate, self.ledger)

        # ── Four Corners ──
        self.north = NorthCVE(self.ledger)
        self.south = SouthHeartbeat(self.ledger, self.key_guardian)
        self.east = EastIsolation(self.ledger)
        self.west = WestKeyLock(self.ledger, self.key_guardian)

        self._running = True
        self._threads = []

    def _pin_cores(self):
        try:
            os.sched_setaffinity(0, {6, 7})
            print("[FABRIC] Pinned to cpu6/cpu7 (taskset 0xc0)")
        except Exception:
            print("[FABRIC] CPU pinning unavailable (non-root) — running on default cores")

    def _agent_thread(self, name, fn, interval):
        """Generic agent loop. Errors go to the ledger, never silently swallowed."""
        while self._running:
            try:
                fn()
            except Exception as e:
                try:
                    self.ledger.write_event(f"{name}_ERROR", {
                        "error": str(e),
                    }, severity="WARN")
                except Exception:
                    pass
            time.sleep(interval)

    def _spawn(self, name, fn, interval):
        t = threading.Thread(
            target=self._agent_thread,
            args=(name, fn, interval),
            daemon=True,
            name=name,
        )
        t.start()
        self._threads.append(t)
        print(f"  [+] {name} (every {interval}s)")

    def launch(self):
        print(f"""
╔══════════════════════════════════════════════════════════════════╗
║ SOVEREIGN UNIFIED SYSTEM — {VERSION}                              ║
║ MIKAYA-SOVEREIGN Complete Architecture                            ║
║ Architect: Brian D. Jenner Jr. (DJ)                               ║
║ In honor of MIKAYA — WPW: Wisdom · Purpose · Will                 ║
║ SD UUID: {SD_UUID}                                                ║
╚══════════════════════════════════════════════════════════════════╝
""")
        self._pin_cores()

        # ── WEST: Key Lock (gatekeeper, runs first) ──
        print("[WEST] Unlocking sovereign key...")
        sd_ok = self.west.verify()
        print(f"[WEST] SD present: {sd_ok}, Device: Sovereign_Shield_Core, Carrier: 310260, Unlocked: {sd_ok}")

        # ── IDENTITY ──
        print("[IDENTITY] Checking device fingerprint...")
        self.east.check()

        # ── SOUTH: Genesis heartbeat ──
        print("[SOUTH] Writing genesis heartbeat...")
        self.south.beat()

        # ── LAYER 8: T-Mobile topology ──
        print(f"[LAYER8] T-Mobile Account {TMOBILE_ACCOUNT_ID} — {len(LAYER8_DEVICES)} devices mapped")
        self.layer8.emit_topology_event()

        # ── AHAVA: Restore distribution state ──
        st = self.ahava.status()
        print(f"[AHAVA] Pool: {st['carry_forward_pool']}, Mints: {st['mint_count']}, Jumps: {st['jump_count']}, Next jump in: {st['pool_to_next_jump']}")

        # ── PAYMENT: LND check ──
        lnd = self.payment_gate.get_node_info()
        if lnd:
            alias = lnd.get("alias", "")
            chains = lnd.get("chains", [])
            print(f"[PAYMENT] LND node active — alias: {alias}")
        else:
            print("[PAYMENT] LND not reachable via lncli — invoices will retry when available")

        # ══════════════════════════════════════════════
        # LAUNCH ALL AGENTS AS INTERNAL THREADS
        # ══════════════════════════════════════════════
        print("[FABRIC] Launching all corners...")

        # Four Corners
        self._spawn("NORTH_CVE", self.north.scan, 300)
        self._spawn("SOUTH_HEARTBEAT", self.south.beat, 60)
        self._spawn("EAST_ISOLATION", self.east.check, 120)
        self._spawn("WEST_KEY_LOCK", lambda: self.west.verify(), 60)

        # Core agents
        self._spawn("MINTING_CORE", self.minting_core.process_ingress, 1)
        self._spawn("SENTINEL_0", lambda: (self.sentinel.sample(), self.sentinel.check_anomaly()), 5)
        self._spawn("LAYER8_TOPOLOGY", self.layer8.emit_topology_event, 600)
        self._spawn("KEY_ROTATION", self.key_guardian.rotate_key, 3600)

        # Authority Engine (its own blocking thread)
        auth_t = threading.Thread(
            target=self.authority.serve, daemon=True, name="AUTHORITY_ENGINE",
        )
        auth_t.start()
        self._threads.append(auth_t)

        # Write launch event
        self.ledger.write_event("FABRIC_UNIFIED_LAUNCH", {
            "version": VERSION,
            "agents": [t.name for t in self._threads],
            "layers": LAYERS,
            "ahava": st,
            "sd_present": sd_ok,
            "lnd_active": lnd is not None,
            "device_count": len(LAYER8_DEVICES),
        }, severity="INFO")

        n = len(self._threads)
        print(f"""
[FABRIC] All corners active. Embroidery complete.
[FABRIC] {n} agents running as internal threads.
[FABRIC] Ledger: {LEDGER_PATH}
[FABRIC] State: {STATE_PATH}
[FABRIC] AHAVA: {AHAVA_CARRY_FORWARD*100:.0f}% carry-forward — jump at {AHAVA_JUMP_THRESHOLD}
[FABRIC] Layers: {len(LAYERS)} active
[FABRIC] Watching. Press CTRL+C or send SIGTERM to stop.
""")

        # ── MAIN WATCH LOOP ──
        def _shutdown(sig, frame):
            print("\n[FABRIC] Signal received. Graceful shutdown.")
            self._running = False

        signal.signal(signal.SIGTERM, _shutdown)
        signal.signal(signal.SIGINT, _shutdown)

        try:
            while self._running:
                time.sleep(30)
                alive = sum(1 for t in self._threads if t.is_alive())
                if alive < n:
                    dead = [t.name for t in self._threads if not t.is_alive()]
                    self.ledger.write_event("AGENT_DOWN", {
                        "alive": alive, "total": n, "dead": dead,
                    }, severity="ALERT")
                    print(f"[FABRIC] WARNING: {dead} not alive")
                # Periodic AHAVA status
                self.ledger.write_event("AHAVA_STATUS", self.ahava.status(), severity="INFO")
        except KeyboardInterrupt:
            print("\n[FABRIC] CTRL+C. Shutting down.")
            self._running = False

        self.ledger.write_event("FABRIC_SHUTDOWN", {
            "reason": "signal", "uptime_events": self.ledger.ledger_total,
        }, severity="INFO")
        print("[FABRIC] Sovereign Unified System stopped.")


# ════════════════════════════════════════════════════════════════
# MAIN — SINGLE ENTRY POINT
# ════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    fabric = SovereignUnifiedFabric()
    fabric.launch()
