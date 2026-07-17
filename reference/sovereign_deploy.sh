#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN One-Shot Deploy
# ═══════════════════════════════════════════════════════════════════
#
# Run ONCE from any fresh Termux session. Handles everything:
#   DNS fix → repo sync (force, no conflicts) → service install
#   → runit clean restart → stack start → L402 gateway test
#
# Usage:
#   bash sovereign_deploy.sh                  # wallet.pw must already exist
#   bash sovereign_deploy.sh 'MY_PASS'        # stores wallet password first
#
# Safe to re-run at any time.
# ═══════════════════════════════════════════════════════════════════

REPO_URL="https://github.com/jenner5familynutz8389-IamDJ/docs"
BRANCH="claude/sovereign-core-2026-i1djxz"
DOCS_DIR="$HOME/sovereign/docs"
LOG_DIR="$HOME/sovereign/logs"
CONF_DIR="$HOME/.config/sovereign"
PASS_FILE="$CONF_DIR/wallet.pw"
SV_DIR="$HOME/.config/runit/sv"

mkdir -p "$LOG_DIR" "$CONF_DIR" "$HOME/sovereign/ledger"
log() { echo "[$(date '+%H:%M:%S')] [DEPLOY] $*"; }

log "========================================================"
log "MIKAYA-SOVEREIGN One-Shot Deploy"
log "========================================================"

# ── 0. Optional wallet password argument ──────────────────────────
if [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    log "Wallet password stored → $PASS_FILE"
fi

# ── 1. Fix DNS ────────────────────────────────────────────────────
log "Setting DNS resolvers..."
{ echo "nameserver 8.8.8.8"; echo "nameserver 1.1.1.1"; } > "$PREFIX/etc/resolv.conf"
log "  DNS: 8.8.8.8 / 1.1.1.1"

# ── 2. Sync repo — force, no conflicts possible ───────────────────
log "Syncing repo from GitHub..."
if [ -d "$DOCS_DIR/.git" ]; then
    # Force-sync: discard any local modifications so checkout never aborts
    chmod -R u+rwX "$DOCS_DIR" 2>/dev/null || true
    git -C "$DOCS_DIR" fetch origin "$BRANCH"
    git -C "$DOCS_DIR" reset --hard "origin/$BRANCH"
    log "  Reset to origin/$BRANCH"
else
    mkdir -p "$(dirname "$DOCS_DIR")"
    git clone --branch "$BRANCH" "$REPO_URL" "$DOCS_DIR"
    log "  Cloned fresh"
fi
chmod -R u+rwX "$DOCS_DIR"
log "  Repo: $(git -C "$DOCS_DIR" log -1 --format='%h %s')"

# ── 3. Python deps ────────────────────────────────────────────────
log "Checking Python deps..."
python3 -c "import requests" 2>/dev/null || pip install --quiet requests
log "  Python deps OK"

# ── 4. Run main service installer ─────────────────────────────────
log "Installing runit services..."
cd "$DOCS_DIR"
bash reference/install_all_sovereign_services.sh || true
log "  Installer done"

# ── 5. Kill all service processes before stopping runsvdir ───────
# Must kill children first — pkill runsvdir alone leaves orphans that
# block port 8443 and prevent the fresh authority-engine from starting.
log "Stopping services and runsvdir..."
pkill -f "authority_engine" 2>/dev/null || true
pkill -f "auto_channel_watcher" 2>/dev/null || true
pkill -f "auto_unlock" 2>/dev/null || true
pkill -f "sovereign_tunnel" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true
pkill -f "runsvdir.*runit/sv" 2>/dev/null || true
sleep 4   # give orphans time to die

# ── 6. Remove stale supervise locks ───────────────────────────────
log "Clearing stale supervise state..."
for svc in lnd authority-engine auto-channel auto-unlock tunnel; do
    rm -rf "$SV_DIR/$svc/supervise"
done

# ── 7. Start runsvdir fresh ───────────────────────────────────────
log "Starting runsvdir..."
runsvdir -P "$SV_DIR" >> "$LOG_DIR/runsvdir.log" 2>&1 &
RUNIT_PID=$!
log "  runsvdir PID $RUNIT_PID — waiting 6s for supervisor init..."
sleep 6

# ── 8. Start each service via sv ──────────────────────────────────
sv_start() {
    local svc="$1"
    local result
    result=$(SVDIR="$SV_DIR" sv start "$svc" 2>&1) && {
        log "  $svc: UP"
    } || {
        echo "$result" | grep -q "already running\|ok: run" && log "  $svc: already running" || log "  $svc: $result"
    }
}

log "Starting services..."
sv_start lnd
sv_start authority-engine
sv_start auto-channel
if command -v cloudflared >/dev/null 2>&1; then
    sv_start tunnel
else
    log "  tunnel: skipped (cloudflared not installed — pkg install cloudflared -y)"
fi

# ── 9. Auto-unlock wallet ─────────────────────────────────────────
if [ -f "$PASS_FILE" ]; then
    log "Launching auto-unlock (background)..."
    bash "$DOCS_DIR/reference/auto_unlock.sh" >> "$LOG_DIR/auto_unlock.log" 2>&1 &
    log "  auto-unlock: PID $!"
else
    log ""
    log "┌─────────────────────────────────────────────────────┐"
    log "│  ACTION REQUIRED: wallet.pw not found               │"
    log "│                                                      │"
    log "│  printf '%s' 'YOUR_WALLET_PASSWORD' \\               │"
    log "│    > $PASS_FILE                │"
    log "│  chmod 600 $PASS_FILE          │"
    log "│                                                      │"
    log "│  Then: bash $DOCS_DIR/reference/auto_unlock.sh │"
    log "└─────────────────────────────────────────────────────┘"
fi

# ── 10. Wait for L402 gateway to go live (up to 5 min) ───────────
log ""
log "Waiting for L402 gateway to go live (max 5 min)..."
log "  Wallet unlock typically takes 30-90s after LND starts."
GATEWAY_OK=0
for attempt in $(seq 1 60); do
    sleep 5
    RESULT=$(curl -s --max-time 4 http://127.0.0.1:8443/query 2>&1) || true

    if echo "$RESULT" | grep -q '"invoice"'; then
        log "  ✓ L402 LIVE (attempt $attempt, $((attempt * 5))s)"
        INVOICE=$(echo "$RESULT" | python3 -c \
            'import sys,json; d=json.load(sys.stdin); print(d.get("invoice","?")[:72]+"...")' \
            2>/dev/null || echo "(parse error)")
        log "  Invoice: $INVOICE"
        GATEWAY_OK=1
        break

    elif echo "$RESULT" | grep -qi '"locked"\|wallet locked\|wallet.*lock'; then
        [ $((attempt % 6)) -eq 1 ] && log "  [${attempt}] wallet still locked — auto-unlock running..."

    elif echo "$RESULT" | grep -qi 'no_tlscert\|no_macaroon'; then
        log "  FATAL: credential file missing — check authority_engine.log"
        log "  $RESULT"
        break

    elif echo "$RESULT" | grep -qi '"lnd_grpc_open": false\|unreachable'; then
        [ $((attempt % 6)) -eq 1 ] && log "  [${attempt}] LND gRPC not open yet — LND starting..."

    else
        [ $((attempt % 6)) -eq 1 ] && log "  [${attempt}] waiting... ($RESULT)"
    fi
done

if [ $GATEWAY_OK -eq 0 ]; then
    log ""
    log "  Gateway not live after $((60 * 5))s. Diagnostics:"
    STATUS=$(curl -s --max-time 5 http://127.0.0.1:8443/status 2>/dev/null || echo "{}")
    NODE_STATUS=$(echo "$STATUS" | python3 -c \
        'import sys,json; d=json.load(sys.stdin); print(d.get("node",{}).get("status","?"))' \
        2>/dev/null || echo "unknown")
    log "  Node status: $NODE_STATUS"
    log "  Full diag:   curl http://127.0.0.1:8443/status"
    log "  Engine log:  tail -50 $LOG_DIR/authority_engine.log"
    log "  Unlock log:  tail -50 $LOG_DIR/auto_unlock.log"
fi

# ── 11. Report public tunnel URL ─────────────────────────────────
TUNNEL_URL=""
for _t in $(seq 1 6); do
    [ -f "$LOG_DIR/tunnel_url.txt" ] && TUNNEL_URL=$(cat "$LOG_DIR/tunnel_url.txt") && break
    sleep 5
done
if [ -n "$TUNNEL_URL" ]; then
    log ""
    log "PUBLIC GATEWAY URL: $TUNNEL_URL"
    log "  (changes on every tunnel restart — current: cat $LOG_DIR/tunnel_url.txt)"
fi

# ── Done ──────────────────────────────────────────────────────────
log ""
log "========================================================"
log "Deploy complete"
log ""
log "STATUS:"
log "  SVDIR=$SV_DIR sv status lnd authority-engine auto-channel"
log ""
log "LOGS:"
log "  tail -f $LOG_DIR/authority_engine.log"
log "  tail -f $LOG_DIR/auto_channel.log"
log "  tail -f $LOG_DIR/auto_unlock.log"
log "  tail -f $LOG_DIR/runsvdir.log"
log ""
log "TEST:"
log "  curl http://127.0.0.1:8443/query"
log "========================================================"
