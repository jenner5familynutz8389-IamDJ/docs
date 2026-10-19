#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN LND runit service run script
# ═══════════════════════════════════════════════════════════════════
#
# INSTALL:
#   cp lnd_runit_run.sh ~/.config/runit/sv/lnd/run
#   chmod +x ~/.config/runit/sv/lnd/run
#
# CPU affinity strategy (FOSSiBOT F110 Pro — Helio G99):
#
#   Cores 0-1  Cortex-A76  big (performance)    — untouched
#   Cores 2-5  Cortex-A55  LITTLE (efficiency)  ← LND lives here
#   Cores 6-7  Cortex-A55  LITTLE (efficiency)  — MIKAYA CORE (fabric)
#
# Pinning LND to cores 2-5 keeps it on efficiency silicon (low mW)
# without competing with MIKAYA's dedicated cores 6-7.  The big
# cores (0-1) stay free for Android UI / camera bursts.
#
# ionice -c 3 (idle I/O):  LND's bbolt writes yield to any other I/O.
#                           Prevents storage latency spikes during sync.
# nice -n 10 :              Scheduler deprioritises LND behind all
#                           normal-priority Android processes.
#
# Together these reduce battery drain in three ways:
#   1. A55 cores run at ~0.2-0.4W vs A76 at ~1.5-2W under load
#   2. I/O idle class reduces eMMC controller wakeups
#   3. Lower nice keeps CPU frequency governor in the energy-efficient
#      range rather than boosting clock for LND's background work
# ═══════════════════════════════════════════════════════════════════

LOG_DIR="$HOME/sovereign/logs"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LND-RUNIT] $*" | tee -a "$LOG_DIR/lnd_service.log"
}

log "Starting LND on A55 efficiency cores 2-5 (ionice=idle, nice=+10)"

# taskset -c 2-5  : bind process to Cortex-A55 cores 2,3,4,5
# ionice -c 3     : idle I/O class (yields to all other I/O)
# nice -n 10      : CPU priority 10 below default (range: -20 best, +19 worst)
exec taskset -c 2-5 ionice -c 3 nice -n 10 lnd 2>&1
