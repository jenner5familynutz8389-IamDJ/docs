#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Master Boot Orchestrator
# ═══════════════════════════════════════════════════════════════════
#
# Starts the full sovereign stack in order:
#   DuraSpeed disable → runsvdir → LND → auto-unlock → L402 engine
#   → auto-channel watcher
#
# INSTALL (Termux:Boot — runs on every device boot):
#   pkg install termux-boot   # if not already installed
#   mkdir -p ~/.termux/boot
#   cp sovereign_start.sh ~/.termux/boot/sovereign_start
#   chmod +x ~/.termux/boot/sovereign_start
#   # Open Termux:Boot app once to grant autostart permission
#
# Or run manually from any Termux session.
# ═══════════════════════════════════════════════════════════════════

LOG_DIR="$HOME/sovereign/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/sovereign_start.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SOVEREIGN-START] $*" | tee -a "$LOG"; }

DOCS_DIR="$HOME/sovereign/docs"
REF="$DOCS_DIR/reference"
SVDIR="$HOME/.config/runit/sv"

log "========================================================"
log "MIKAYA-SOVEREIGN boot sequence starting"
log "========================================================"

# ── 1. Disable MediaTek DuraSpeed ────────────────────────────────
DURASPEED_SCRIPT="$HOME/.termux/boot/disable_duraspeed"
if [ -x "$DURASPEED_SCRIPT" ]; then
    log "Disabling DuraSpeed..."
    bash "$DURASPEED_SCRIPT" >> "$LOG" 2>&1 || true
else
    log "INFO: DuraSpeed script not at $DURASPEED_SCRIPT (skipping)"
fi

# ── 2. Pull latest config from repo ──────────────────────────────
if [ -d "$DOCS_DIR/.git" ]; then
    log "Pulling latest sovereign config..."
    git -C "$DOCS_DIR" pull --ff-only origin claude/sovereign-core-2026-i1djxz \
        >> "$LOG" 2>&1 || log "WARN: git pull failed — running with existing config"
fi

# ── 3. Start runit supervisor ─────────────────────────────────────
if pgrep -f "runsvdir.*runit/sv" >/dev/null 2>&1; then
    log "runsvdir already running"
else
    log "Starting runsvdir..."
    runsvdir -P "$SVDIR" >> "$LOG_DIR/runsvdir.log" 2>&1 &
    RUNIT_PID=$!
    sleep 2
    log "runsvdir started (PID: $RUNIT_PID)"
fi

sv_cmd() {
    SVDIR="$HOME/.config/runit/sv" sv "$@" 2>&1
}

# ── 4. Start LND ─────────────────────────────────────────────────
log "Starting LND service..."
sv_cmd start lnd && log "LND: started" || log "LND: already running or start failed"

# ── 5. Auto-unlock wallet (background — waits for LND gRPC) ──────
if [ -f "$REF/auto_unlock.sh" ]; then
    log "Launching auto-unlock in background..."
    bash "$REF/auto_unlock.sh" >> "$LOG" 2>&1 &
    log "Auto-unlock running (PID: $!)"
else
    log "WARN: auto_unlock.sh not found at $REF/auto_unlock.sh"
    log "      Run: bash reference/install_all_sovereign_services.sh"
fi

# ── 6. Start Authority Engine (L402 gateway on :8443) ────────────
log "Starting Authority Engine..."
sv_cmd start authority-engine && log "Authority Engine: started" || \
    log "WARN: authority-engine service not installed yet"

# ── 7. Start Auto Channel Watcher ────────────────────────────────
log "Starting Auto Channel Watcher..."
sv_cmd start auto-channel && log "Auto Channel Watcher: started" || \
    log "WARN: auto-channel service not installed yet"

log "========================================================"
log "Boot sequence complete"
log ""
log "  LND logs:          tail -f ~/sovereign/lnd/logs/lnd.log"
log "  Unlock log:        tail -f $LOG_DIR/auto_unlock.log"
log "  Authority Engine:  tail -f $LOG_DIR/authority_engine.log"
log "  Channel Watcher:   tail -f $LOG_DIR/auto_channel.log"
log "  Ledger:            tail -f ~/sovereign/ledger/event_spine.jsonl"
log ""
log "  Test L402:         curl http://127.0.0.1:8443/query"
log "  Wallet balance:    lncli_s walletbalance"
log "  Node info:         lncli_s getinfo"
log "========================================================"
