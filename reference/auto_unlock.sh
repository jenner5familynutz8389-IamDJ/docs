#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Auto Wallet Unlock
# ═══════════════════════════════════════════════════════════════════
#
# Waits for LND gRPC to open, then unlocks the wallet automatically
# using the password stored in ~/.config/sovereign/wallet.pw
#
# SETUP (one time only):
#   mkdir -p ~/.config/sovereign
#   printf '%s' 'YOUR_WALLET_PASSWORD' > ~/.config/sovereign/wallet.pw
#   chmod 600 ~/.config/sovereign/wallet.pw
# ═══════════════════════════════════════════════════════════════════

PASS_FILE="$HOME/.config/sovereign/wallet.pw"
MACAROON="$HOME/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
LOG_DIR="$HOME/sovereign/logs"
LOG="$LOG_DIR/auto_unlock.log"
LOCKFILE="$LOG_DIR/auto_unlock.lock"
GRPC_PORT=10009

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO-UNLOCK] $*" | tee -a "$LOG"; }

# ── Single-instance guard ─────────────────────────────────────────
if [ -f "$LOCKFILE" ]; then
    LOCKED_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$LOCKED_PID" ] && kill -0 "$LOCKED_PID" 2>/dev/null; then
        exit 0  # another instance is already running — do nothing
    fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# ── Discover TLS cert at runtime ──────────────────────────────────
TLSCERT=""
for _c in \
    "$HOME/.lnd/tls.cert" \
    "$HOME/sovereign/lnd/tls.cert" \
    "$HOME/sovereign/lnd/data/tls.cert"; do
    [ -f "$_c" ] && { TLSCERT="$_c"; break; }
done
if [ -z "$TLSCERT" ]; then
    TLSCERT=$(find "$HOME" -maxdepth 6 -name "tls.cert" 2>/dev/null | head -1)
fi
if [ -z "$TLSCERT" ]; then
    log "ERROR: tls.cert not found. Is LND running?"
    log "  Try: find ~ -name tls.cert 2>/dev/null"
    exit 1
fi
log "TLS cert: $TLSCERT"

# ── Check password file ───────────────────────────────────────────
if [ ! -f "$PASS_FILE" ]; then
    log "ERROR: $PASS_FILE missing"
    log "  Fix: printf '%s' 'your-lnd-password' > $PASS_FILE && chmod 600 $PASS_FILE"
    exit 1
fi
chmod 600 "$PASS_FILE"

PW_CONTENT="$(cat "$PASS_FILE")"
if [ -z "$PW_CONTENT" ]; then
    log "ERROR: $PASS_FILE is empty"
    exit 1
fi
case "$PW_CONTENT" in
    YOUR_*|PLACEHOLDER*|PASSWORD*|"<"*|"["*)
        log "ERROR: $PASS_FILE still has placeholder text: $PW_CONTENT"
        log "  Fix: printf '%s' 'your-real-password' > $PASS_FILE && chmod 600 $PASS_FILE"
        exit 1
        ;;
esac

# ── Wait for LND gRPC port ────────────────────────────────────────
# Use bash /dev/tcp — no netcat required
log "Waiting for LND gRPC on port $GRPC_PORT..."
WAITED=0
MAX_WAIT=300
tcp_open() { (echo > /dev/tcp/127.0.0.1/$GRPC_PORT) 2>/dev/null; }
while ! tcp_open; do
    sleep 3
    WAITED=$((WAITED + 3))
    [ $((WAITED % 30)) -eq 0 ] && log "  still waiting (${WAITED}s)..."
    if [ $WAITED -ge $MAX_WAIT ]; then
        log "ERROR: LND gRPC not up after ${MAX_WAIT}s"
        exit 1
    fi
done
log "LND gRPC open (waited ${WAITED}s)"
sleep 2

# ── Check if already unlocked ─────────────────────────────────────
if lncli --macaroonpath "$MACAROON" --tlscertpath "$TLSCERT" getinfo \
        >/dev/null 2>&1; then
    log "Wallet already unlocked — done"
    exit 0
fi

# ── Unlock ────────────────────────────────────────────────────────
log "Wallet locked. Unlocking now..."
RESULT=$(printf '%s' "$(cat "$PASS_FILE")" | \
    lncli --tlscertpath "$TLSCERT" \
          --macaroonpath "$MACAROON" \
          unlock --stdin 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    log "Wallet unlocked successfully"
elif echo "$RESULT" | grep -qi "invalid passphrase"; then
    log "ERROR: Wrong password in $PASS_FILE"
    exit 1
elif echo "$RESULT" | grep -qi "already unlocked\|already open"; then
    log "Wallet was already unlocked"
else
    log "Unlock result (code $EXIT_CODE): $RESULT"
fi
