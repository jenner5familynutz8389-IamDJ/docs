#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN — Apply LND battery optimizations in one shot
# ═══════════════════════════════════════════════════════════════════
#
# Run this script ONCE on the phone after pulling the repo.
# It replaces ~/.lnd/lnd.conf and the runit run script,
# then restarts the LND service.
#
# Usage (run from repo root):
#   bash reference/lnd_apply_battery_fix.sh
#
# Safe to re-run: backs up existing config before overwriting.
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HOME/sovereign/logs/battery_apply.log"
mkdir -p "$HOME/sovereign/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== LND battery fix apply starting ==="

# ─────────────────────────────────────────────────
# 1. Verify taskset and ionice are available
# ─────────────────────────────────────────────────
for cmd in taskset ionice nice lnd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "ERROR: '$cmd' not found. Install with: pkg install util-linux"
        exit 1
    fi
done
log "OK: taskset / ionice / nice / lnd all present"

# ─────────────────────────────────────────────────
# 2. Stop LND service before modifying config
# ─────────────────────────────────────────────────
if command -v sv >/dev/null 2>&1; then
    log "Stopping LND service via runit..."
    sv stop lnd 2>/dev/null && log "  LND stopped" || log "  LND was not running (OK)"
else
    log "INFO: runit sv not found — stop LND manually before continuing if it is running"
fi

# ─────────────────────────────────────────────────
# 3. Backup and replace lnd.conf
# ─────────────────────────────────────────────────
CONF="$HOME/.lnd/lnd.conf"
mkdir -p "$HOME/.lnd"

if [ -f "$CONF" ]; then
    BACKUP="${CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$CONF" "$BACKUP"
    log "Backed up existing lnd.conf → $BACKUP"
fi

cp "$SCRIPT_DIR/lnd_battery_optimized.conf" "$CONF"
log "Installed optimized lnd.conf → $CONF"

# ─────────────────────────────────────────────────
# 4. Backup and replace runit run script
# ─────────────────────────────────────────────────
RUNIT_DIR="$HOME/.config/runit/sv/lnd"
RUNIT_RUN="$RUNIT_DIR/run"
mkdir -p "$RUNIT_DIR"

if [ -f "$RUNIT_RUN" ]; then
    RBAK="${RUNIT_RUN}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$RUNIT_RUN" "$RBAK"
    log "Backed up existing runit run → $RBAK"
fi

cp "$SCRIPT_DIR/lnd_runit_run.sh" "$RUNIT_RUN"
chmod +x "$RUNIT_RUN"
log "Installed CPU-pinned runit run script → $RUNIT_RUN"

# ─────────────────────────────────────────────────
# 5. Restart LND service
# ─────────────────────────────────────────────────
if command -v sv >/dev/null 2>&1; then
    log "Starting LND service..."
    sv start lnd && log "LND started" || log "WARN: sv start failed — start manually with: sv start lnd"
else
    log "Start LND manually: runsvdir -P ~/.config/runit/sv & then sv start lnd"
fi

log "=== Apply complete. LND now pinned to A55 cores 2-5. ==="
log "    Monitor: sv status lnd"
log "    Logs:    tail -f ~/sovereign/lnd/logs/lnd.log"
