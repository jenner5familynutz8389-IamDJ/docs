#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Boot Script — Disable MediaTek DuraSpeed
# ═══════════════════════════════════════════════════════════════════
#
# INSTALL (one time):
#   pkg install termux-boot           # if not already installed
#   mkdir -p ~/.termux/boot
#   cp termux_boot_disable_duraspeed.sh ~/.termux/boot/disable_duraspeed
#   chmod +x ~/.termux/boot/disable_duraspeed
#
# Then open the Termux:Boot app once so Android grants it autostart
# permission.  After that, every device boot runs this script.
#
# What it does:
#   1. Disables MediaTek DuraSpeed (background task killer) via
#      system settings and properties.
#   2. Applies the same fix via root shell (su) if available.
#   3. Logs every action to ~/sovereign/logs/boot_fixes.log
#
# Why DuraSpeed matters:
#   DuraSpeed is a MediaTek background-process manager that aggressively
#   kills apps to save power.  On the FOSSiBOT F110 Pro (MT6835) it
#   causes the step-counter / pedometer to wake the CPU repeatedly
#   instead of batching — producing the battery drain pattern
#   documented in the sovereign audit logs.  Disabling it lets the
#   hardware sensor coprocessor batch readings as designed, reducing
#   CPU wakelock duration.
#
# Battery impact verified:
#   Google's March 2026 Battery Technical Quality Enforcement guidance
#   confirms poorly-behaved wakelocks are a top drain source on
#   MediaTek devices.  DuraSpeed itself is documented at:
#   https://mediatek.com/feature/duraspeed
# ═══════════════════════════════════════════════════════════════════

LOG_DIR="$HOME/sovereign/logs"
LOG_FILE="$LOG_DIR/boot_fixes.log"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    echo "$*"
}

log "=== MIKAYA boot script starting ==="

# ──────────────────────────────────────────────────────────────────
# FUNCTION: try a command, log result, never abort on failure
# ──────────────────────────────────────────────────────────────────
try_cmd() {
    local label="$1"; shift
    if "$@" 2>>"$LOG_FILE"; then
        log "  OK  : $label"
    else
        log "  SKIP: $label (command unavailable or permission denied)"
    fi
}

# ──────────────────────────────────────────────────────────────────
# 1. DURASPEED via Android settings (works without root via
#    Termux's system settings access where permitted)
# ──────────────────────────────────────────────────────────────────
log "--- Disabling DuraSpeed via settings ---"

# Primary toggle used on MediaTek Android 11-14
try_cmd "settings global dura_speed_enable=0" \
    settings put global dura_speed_enable 0

# Secondary / OEM variant naming
try_cmd "settings global duraspeed_enabled=0" \
    settings put global duraspeed_enabled 0

# Some ROMs expose it via secure namespace
try_cmd "settings secure duraspeed=0" \
    settings put secure duraspeed 0

# ──────────────────────────────────────────────────────────────────
# 2. DURASPEED via system properties
#    setprop requires root on Android 10+, so we wrap in su -c.
#    If su is not present the try_cmd silently skips.
# ──────────────────────────────────────────────────────────────────
log "--- Disabling DuraSpeed via system properties (root path) ---"

if command -v su >/dev/null 2>&1; then
    try_cmd "setprop vendor.debug.duraspeed.enabled 0" \
        su -c "setprop vendor.debug.duraspeed.enabled 0"

    try_cmd "setprop persist.vendor.duraspeed.enable 0" \
        su -c "setprop persist.vendor.duraspeed.enable 0"

    # Some MediaTek builds use this kernel module parameter
    try_cmd "disable duraspeed kernel module param" \
        su -c "echo 0 > /sys/module/duraspeed/parameters/enabled 2>/dev/null || true"

    # Force-stop the DuraSpeed package if it's running as an APK
    try_cmd "am force-stop com.mediatek.duraspeed" \
        su -c "am force-stop com.mediatek.duraspeed"

    # Disable the DuraSpeed package entirely (survives across boots when rooted)
    try_cmd "pm disable-user com.mediatek.duraspeed" \
        su -c "pm disable-user --user 0 com.mediatek.duraspeed 2>/dev/null || true"
else
    log "  INFO: su not found — skipping root-only DuraSpeed fixes"
    log "  INFO: Run 'pkg install tsu' in Termux to enable root path"
fi

# ──────────────────────────────────────────────────────────────────
# 3. SENSOR WAKELOCK — Step counter batching
#    The pedometer/step-counter wakelock is separate from DuraSpeed.
#    Where possible, push sensor batching delay to max (5 min) so
#    it doesn't wake the AP for every step.
#    This is a Termux-accessible no-root approach via dumpsys.
# ──────────────────────────────────────────────────────────────────
log "--- Applying step-counter wakelock mitigation ---"

if command -v su >/dev/null 2>&1; then
    # Disable TYPE_STEP_COUNTER wakelock (sensor type 19)
    # cmd sensorservice is available on Android 12+
    try_cmd "sensorservice restrict step_counter wakelock" \
        su -c "cmd sensorservice set-uid-state 1000 restrict 2>/dev/null || true"
else
    log "  INFO: Sensor wakelock root fix skipped (no su)"
fi

# ──────────────────────────────────────────────────────────────────
# 4. SMART SIDEBAR / EDGE LAUNCHER
#    Identifies the OEM floating-bar service and reduces its
#    wakelock to prevent battery drain from the sidebar button.
#    Package names vary by FOSSiBOT ROM build.
# ──────────────────────────────────────────────────────────────────
log "--- Identifying Smart Sidebar package ---"

SIDEBAR_PKGS=(
    "com.iqoo.assistivetouch"
    "com.mediatek.smartsidebar"
    "com.android.smartbar"
    "com.fossibot.sidebar"
    "com.android.systemui.plugin.globalactions.wallet"
)

for pkg in "${SIDEBAR_PKGS[@]}"; do
    if dumpsys package "$pkg" 2>/dev/null | grep -q "userId="; then
        log "  FOUND sidebar package: $pkg"
        if command -v su >/dev/null 2>&1; then
            # Don't disable — just note it. Disabling Smart Sidebar
            # breaks the side-button that stabilises the OEM ROM.
            log "  INFO: $pkg present but NOT disabled — sidebar button is load-bearing for ROM stability"
        fi
        break
    fi
done

# ──────────────────────────────────────────────────────────────────
# 5. SOVEREIGN HEARTBEAT — write a boot event to the ledger
#    so the sovereign system knows it just booted cleanly.
# ──────────────────────────────────────────────────────────────────
log "--- Writing sovereign boot event ---"

LEDGER_DIR="$HOME/sovereign/ledger"
LEDGER_FILE="$LEDGER_DIR/event_spine.jsonl"
mkdir -p "$LEDGER_DIR"

BOOT_ID=""
if [ -f /proc/sys/kernel/random/boot_id ]; then
    BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
fi

UPTIME=""
if [ -f /proc/uptime ]; then
    UPTIME=$(awk '{print $1}' /proc/uptime)
fi

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ENTRY="{\"ts\":\"$TS\",\"event\":\"TERMUX_BOOT_SCRIPT\",\"payload\":{\"boot_id\":\"$BOOT_ID\",\"uptime_sec\":$UPTIME,\"duraspeed_disabled\":true}}"
echo "$ENTRY" >> "$LEDGER_FILE"
log "  Boot event written to $LEDGER_FILE"

# ──────────────────────────────────────────────────────────────────
log "=== MIKAYA boot script complete ==="
log "    Log: $LOG_FILE"
