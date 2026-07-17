#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN — Full Service Installer
# ═══════════════════════════════════════════════════════════════════
#
# Run ONCE after cloning/pulling the repo on the phone.
# Wires up all runit services, Termux:Boot scripts, aliases,
# and sets up the wallet password file.
#
# Usage (from repo root):
#   bash reference/install_all_sovereign_services.sh
#
# Safe to re-run — backs up existing files before overwriting.
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVDIR="$HOME/.config/runit/sv"
BOOT_DIR="$HOME/.termux/boot"
CONF_DIR="$HOME/.config/sovereign"
BIN_DIR="$HOME/bin"
LOG_DIR="$HOME/sovereign/logs"

mkdir -p "$SVDIR" "$BOOT_DIR" "$CONF_DIR" "$BIN_DIR" "$LOG_DIR"
mkdir -p "$HOME/sovereign/ledger"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
backup() {
    [ -f "$1" ] && cp "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)" && log "  Backed up: $1" || true
}

log "=== MIKAYA-SOVEREIGN Full Service Install ==="
log ""

# ── 0. Python requests library ────────────────────────────────────
log "Checking Python dependencies..."
python3 -c "import requests" 2>/dev/null || {
    log "  Installing requests..."
    pip install requests
}
log "  Python deps OK"

# ── 1. lncli sovereign wrapper ────────────────────────────────────
backup "$BIN_DIR/lncli_sovereign"
cp "$SCRIPT_DIR/lncli_sovereign.sh" "$BIN_DIR/lncli_sovereign"
chmod +x "$BIN_DIR/lncli_sovereign"
log "Installed: lncli_sovereign wrapper → $BIN_DIR/lncli_sovereign"

# ── 2. Shell aliases (.bashrc) ────────────────────────────────────
MARKER="# === MIKAYA-SOVEREIGN aliases ==="
BASHRC="$HOME/.bashrc"
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    log "Shell aliases already in $BASHRC — skipping"
else
    cat >> "$BASHRC" <<'ALIASEOF'

# === MIKAYA-SOVEREIGN aliases ===
export PATH="$HOME/bin:$PATH"
export SVDIR="$HOME/.config/runit/sv"

alias lncli_s='~/bin/lncli_sovereign'
alias sv_lnd='SVDIR=$HOME/.config/runit/sv sv'

sovereign_start_runit() {
    if ! pgrep -f "runsvdir.*runit/sv" >/dev/null 2>&1; then
        runsvdir -P "$HOME/.config/runit/sv" &
        echo "runsvdir started (PID $!)"
    else
        echo "runsvdir already running"
    fi
}
# === end MIKAYA-SOVEREIGN aliases ===
ALIASEOF
    log "Shell aliases added to $BASHRC"
fi

# ── 3. Runit service: lnd (already exists — leave intact) ─────────
log "LND runit service: checking..."
if [ -f "$SVDIR/lnd/run" ]; then
    log "  lnd run script already present — skipping"
else
    backup "$SVDIR/lnd/run"
    mkdir -p "$SVDIR/lnd"
    cp "$SCRIPT_DIR/lnd_runit_run.sh" "$SVDIR/lnd/run"
    chmod +x "$SVDIR/lnd/run"
    log "  Installed: $SVDIR/lnd/run"
fi

# ── 4. Runit service: authority-engine (L402 gateway) ─────────────
log "Installing runit service: authority-engine..."
mkdir -p "$SVDIR/authority-engine"
backup "$SVDIR/authority-engine/run"
cat > "$SVDIR/authority-engine/run" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
exec taskset -c 2-5 ionice -c 3 nice -n 10 \\
    python3 $SCRIPT_DIR/authority_engine.py 2>&1
RUNEOF
chmod +x "$SVDIR/authority-engine/run"
log "  Installed: $SVDIR/authority-engine/run"

# ── 5. Runit service: auto-channel (channel watcher) ──────────────
log "Installing runit service: auto-channel..."
mkdir -p "$SVDIR/auto-channel"
backup "$SVDIR/auto-channel/run"
cat > "$SVDIR/auto-channel/run" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
exec taskset -c 2-5 ionice -c 3 nice -n 10 \\
    python3 $SCRIPT_DIR/auto_channel_watcher.py 2>&1
RUNEOF
chmod +x "$SVDIR/auto-channel/run"
log "  Installed: $SVDIR/auto-channel/run"

# ── 6. Runit service: auto-unlock (wallet unlock on boot) ─────────
# One-shot pattern: run auto_unlock.sh then sleep 23h so runit does
# NOT loop-restart it on failure. sv restart auto-unlock to re-run manually.
log "Installing runit service: auto-unlock..."
mkdir -p "$SVDIR/auto-unlock"
backup "$SVDIR/auto-unlock/run"
cat > "$SVDIR/auto-unlock/run" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
bash $SCRIPT_DIR/auto_unlock.sh
# Hold the slot — runit must see a running process or it restarts us.
# 23h sleep means one auto-unlock attempt per reboot, never a spin loop.
exec sleep 82800
RUNEOF
chmod +x "$SVDIR/auto-unlock/run"
log "  Installed: $SVDIR/auto-unlock/run (one-shot, 23h hold)"

# ── 6b. Runit service: tunnel (public URL via Cloudflare) ─────────
log "Installing runit service: tunnel..."
mkdir -p "$SVDIR/tunnel"
backup "$SVDIR/tunnel/run"
cat > "$SVDIR/tunnel/run" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
exec bash $SCRIPT_DIR/sovereign_tunnel.sh 2>&1
RUNEOF
chmod +x "$SVDIR/tunnel/run"
log "  Installed: $SVDIR/tunnel/run"
command -v cloudflared >/dev/null 2>&1 || \
    log "  NOTE: cloudflared not installed yet — run: pkg install cloudflared -y"

# ── 7. DuraSpeed boot script ──────────────────────────────────────
log "Installing DuraSpeed boot script..."
backup "$BOOT_DIR/disable_duraspeed"
cp "$SCRIPT_DIR/termux_boot_disable_duraspeed.sh" "$BOOT_DIR/disable_duraspeed"
chmod +x "$BOOT_DIR/disable_duraspeed"
log "  Installed: $BOOT_DIR/disable_duraspeed"

# ── 8. Master sovereign boot script ──────────────────────────────
log "Installing sovereign master boot script..."
backup "$BOOT_DIR/sovereign_start"
cp "$SCRIPT_DIR/sovereign_start.sh" "$BOOT_DIR/sovereign_start"
chmod +x "$BOOT_DIR/sovereign_start"
log "  Installed: $BOOT_DIR/sovereign_start"

# ── 9. Wallet password file ───────────────────────────────────────
PASS_FILE="$CONF_DIR/wallet.pw"
if [ -f "$PASS_FILE" ]; then
    chmod 600 "$PASS_FILE"
    log "Wallet password file already exists at $PASS_FILE (chmod 600 confirmed)"
else
    log ""
    log "┌─────────────────────────────────────────────────────────┐"
    log "│  ACTION REQUIRED: Store your wallet password           │"
    log "│                                                         │"
    log "│  echo 'YOUR_WALLET_PASSWORD' > $PASS_FILE  │"
    log "│  chmod 600 $PASS_FILE              │"
    log "│                                                         │"
    log "│  This enables auto-unlock on every boot.               │"
    log "└─────────────────────────────────────────────────────────┘"
fi

# ── Done ──────────────────────────────────────────────────────────
log ""
log "=== Install complete ==="
log ""
log "NEXT STEPS:"
log ""
log "  1. Store wallet password (if not done):"
log "     echo 'PASSWORD' > $PASS_FILE && chmod 600 $PASS_FILE"
log ""
log "  2. Apply shell aliases in current session:"
log "     source ~/.bashrc"
log ""
log "  3. Start the full sovereign stack:"
log "     bash reference/sovereign_start.sh"
log ""
log "  That's it. On next device reboot, Termux:Boot runs"
log "  sovereign_start automatically."
log ""
log "SERVICES INSTALLED:"
log "  lnd               → Lightning Network Daemon (CPU-pinned A55 cores)"
log "  authority-engine  → L402 micropayment gateway on :8443"
log "  auto-channel      → watches balance, opens channel when funded"
log "  auto-unlock       → unlocks wallet on every boot"
log "  tunnel            → public HTTPS URL for the gateway (cat ~/sovereign/logs/tunnel_url.txt)"
log ""
log "TEST (after starting stack):"
log "  curl http://127.0.0.1:8443/query"
log "  # Returns 402 + Lightning invoice — system is live"
