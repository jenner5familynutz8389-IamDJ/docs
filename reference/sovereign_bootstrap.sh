#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Bootstrap — fresh device, zero packages installed
# ═══════════════════════════════════════════════════════════════════
#
# Takes a BRAND NEW Termux install to a fully provisioned sovereign
# device: packages, repo, LND config, directories. After this, restore
# or create the wallet, then run sovereign_deploy.sh.
#
# Tested targets: FOSSiBOT F110 Pro (Helio G99),
#                 Motorola G Power 5G 2023 (Dimensity 930, Android 14)
# Both enumerate Cortex-A55 efficiency cores at cpu0-5, so the
# taskset -c 2-5 pinning in the service scripts works unchanged.
#
# PREREQS (installed as Android apps, from F-Droid — NOT Play Store):
#   1. Termux
#   2. Termux:Boot   (for auto-start on reboot)
#
# USAGE (paste into a fresh Termux session):
#   curl -sL https://raw.githubusercontent.com/jenner5familynutz8389-IamDJ/docs/claude/sovereign-core-2026-i1djxz/reference/sovereign_bootstrap.sh | bash
# or if the repo is already cloned:
#   bash ~/sovereign/docs/reference/sovereign_bootstrap.sh
# ═══════════════════════════════════════════════════════════════════

REPO_URL="https://github.com/jenner5familynutz8389-IamDJ/docs"
BRANCH="claude/sovereign-core-2026-i1djxz"
DOCS_DIR="$HOME/sovereign/docs"

log() { echo "[$(date '+%H:%M:%S')] [BOOTSTRAP] $*"; }

log "========================================================"
log "MIKAYA-SOVEREIGN Device Bootstrap"
log "========================================================"

# ── 1. DNS first — fresh Termux often can't resolve ───────────────
{ echo "nameserver 8.8.8.8"; echo "nameserver 1.1.1.1"; } > "$PREFIX/etc/resolv.conf"
log "DNS: 8.8.8.8 / 1.1.1.1"

# ── 2. Package base ───────────────────────────────────────────────
log "Updating package index..."
pkg update -y 2>&1 | tail -1 || true

log "Installing packages: git python lnd runit cloudflared curl util-linux openssl-tool..."
pkg install -y git python lnd runit cloudflared curl util-linux openssl-tool 2>&1 | tail -3
for bin in git python3 lnd lncli runsvdir cloudflared curl taskset; do
    command -v "$bin" >/dev/null 2>&1 \
        && log "  $bin: OK" \
        || log "  $bin: MISSING — install manually: pkg install <package>"
done

log "Installing Python requests..."
python3 -c "import requests" 2>/dev/null || pip install --quiet requests
log "  requests: OK"

# ── 3. Directory skeleton ─────────────────────────────────────────
mkdir -p "$HOME/sovereign/logs" "$HOME/sovereign/ledger" \
         "$HOME/sovereign/lnd/data" "$HOME/.lnd" \
         "$HOME/.config/sovereign" "$HOME/.config/runit/sv" \
         "$HOME/bin" "$HOME/.termux/boot"
log "Directory skeleton created"

# ── 4. Repo ───────────────────────────────────────────────────────
if [ -d "$DOCS_DIR/.git" ]; then
    git -C "$DOCS_DIR" fetch origin "$BRANCH"
    git -C "$DOCS_DIR" reset --hard "origin/$BRANCH"
    log "Repo updated: $(git -C "$DOCS_DIR" log -1 --format='%h %s')"
else
    mkdir -p "$(dirname "$DOCS_DIR")"
    git clone --branch "$BRANCH" "$REPO_URL" "$DOCS_DIR"
    log "Repo cloned: $(git -C "$DOCS_DIR" log -1 --format='%h %s')"
fi

# ── 5. LND config ─────────────────────────────────────────────────
if [ -f "$HOME/.lnd/lnd.conf" ]; then
    log "lnd.conf already present — leaving intact"
else
    cp "$DOCS_DIR/reference/lnd_battery_optimized.conf" "$HOME/.lnd/lnd.conf"
    log "Installed lnd.conf (battery-optimized, neutrino mainnet)"
fi

# ── 6. Storage access (for wallet backup transfer) ────────────────
if [ ! -d "$HOME/storage" ]; then
    log "Requesting shared-storage access (approve the Android prompt)..."
    termux-setup-storage || true
fi

# ── Done — wallet is the ONLY manual step left ────────────────────
log ""
log "========================================================"
log "Bootstrap complete. WALLET is the one manual step left."
log ""
log "MIGRATING an existing node (keep same identity/pubkey):"
log "  Read: $DOCS_DIR/reference/DEVICE_MIGRATION.md"
log "  CRITICAL: stop LND on the old device FIRST."
log ""
log "FRESH node (new identity):"
log "  1. lnd &                       # let it initialize, ~20s"
log "  2. lncli --tlscertpath ~/.lnd/tls.cert create"
log "     → set a password, WRITE DOWN the 24-word seed on paper"
log "  3. printf '%s' 'YOUR_PASSWORD' > ~/.config/sovereign/wallet.pw"
log "     chmod 600 ~/.config/sovereign/wallet.pw"
log "  4. pkill lnd"
log ""
log "THEN deploy the full stack:"
log "  bash $DOCS_DIR/reference/sovereign_deploy.sh"
log "========================================================"
