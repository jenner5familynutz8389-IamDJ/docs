#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Auto Wallet Unlock
# ═══════════════════════════════════════════════════════════════════
#
# Waits for LND gRPC to open, then unlocks the wallet automatically
# using the password stored in ~/.config/sovereign/wallet.pw
#
# Called by sovereign_start.sh on every boot / new Termux session.
# Also installable as a standalone runit service.
#
# SETUP (one time only):
#   mkdir -p ~/.config/sovereign
#   echo 'YOUR_WALLET_PASSWORD' > ~/.config/sovereign/wallet.pw
#   chmod 600 ~/.config/sovereign/wallet.pw
#
# SECURITY TRADEOFF:
#   Password is stored in plaintext on device storage (chmod 600).
#   Anyone with shell access to this phone can read it.
#   Acceptable for a personal sovereign node — physical device is
#   the security boundary. Do NOT put this file in the git repo.
# ═══════════════════════════════════════════════════════════════════

PASS_FILE="$HOME/.config/sovereign/wallet.pw"
MACAROON="$HOME/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
TLSCERT="$HOME/sovereign/lnd/data/tls.cert"
LOG_DIR="$HOME/sovereign/logs"
LOG="$LOG_DIR/auto_unlock.log"
GRPC_PORT=10009

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO-UNLOCK] $*" | tee -a "$LOG"; }

# ── Check password file ───────────────────────────────────────────
if [ ! -f "$PASS_FILE" ]; then
    log "ERROR: Password file missing: $PASS_FILE"
    log "Fix: mkdir -p ~/.config/sovereign && echo 'YOUR_PASSWORD' > $PASS_FILE && chmod 600 $PASS_FILE"
    exit 1
fi
chmod 600 "$PASS_FILE"

# ── Wait for LND gRPC port ────────────────────────────────────────
log "Waiting for LND gRPC on port $GRPC_PORT..."
WAITED=0
MAX_WAIT=300  # 5 minutes
while ! nc -z 127.0.0.1 $GRPC_PORT 2>/dev/null; do
    sleep 3
    WAITED=$((WAITED + 3))
    if [ $WAITED -ge $MAX_WAIT ]; then
        log "ERROR: LND gRPC did not come up after ${MAX_WAIT}s. Is LND running?"
        exit 1
    fi
done
log "LND gRPC is up (waited ${WAITED}s)"

# Give LND 2 more seconds to fully initialize the wallet locker
sleep 2

# ── Check if already unlocked ─────────────────────────────────────
# lncli getinfo works only when wallet is unlocked
if lncli --macaroonpath "$MACAROON" --tlscertpath "$TLSCERT" getinfo \
        >/dev/null 2>&1; then
    log "Wallet already unlocked — nothing to do"
    exit 0
fi

# ── Unlock ────────────────────────────────────────────────────────
log "Wallet is locked. Unlocking now..."

# lncli unlock reads password from stdin when stdin is not a TTY
RESULT=$(printf '%s' "$(cat "$PASS_FILE")" | \
    lncli --tlscertpath "$TLSCERT" \
          --macaroonpath "$MACAROON" \
          unlock --stdin 2>&1)

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    log "Wallet unlocked successfully"
elif echo "$RESULT" | grep -qi "invalid passphrase"; then
    log "ERROR: Wrong password. Update $PASS_FILE"
    exit 1
elif echo "$RESULT" | grep -qi "already unlocked\|already open"; then
    log "Wallet was already unlocked"
else
    log "Unlock attempt result (code $EXIT_CODE): $RESULT"
    # Non-fatal — wallet may have unlocked via another path
fi
