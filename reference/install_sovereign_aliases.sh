#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN — Install shell aliases and lncli wrapper
# ═══════════════════════════════════════════════════════════════════
#
# Run once after cloning the repo:
#   bash reference/install_sovereign_aliases.sh
#
# What it does:
#   1. Installs lncli_sovereign wrapper to ~/bin/
#   2. Adds alias lncli_s → lncli_sovereign to ~/.bashrc
#   3. Adds SVDIR env var so plain `sv` commands work without prefix
#
# After install, open a new Termux session (or run: source ~/.bashrc)
# Then use:
#   lncli_s newaddress p2wkh
#   lncli_s getinfo
#   lncli_s walletbalance
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
BIN_DIR="$HOME/bin"

mkdir -p "$BIN_DIR"

# ─── 1. Install lncli wrapper ──────────────────────────────────────
cp "$SCRIPT_DIR/lncli_sovereign.sh" "$BIN_DIR/lncli_sovereign"
chmod +x "$BIN_DIR/lncli_sovereign"
echo "Installed: $BIN_DIR/lncli_sovereign"

# ─── 2. Add aliases to .bashrc (idempotent) ───────────────────────
MARKER="# === MIKAYA-SOVEREIGN aliases ==="

if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    echo "Aliases already present in $BASHRC — skipping"
else
    cat >> "$BASHRC" <<'EOF'

# === MIKAYA-SOVEREIGN aliases ===
export PATH="$HOME/bin:$PATH"

# lncli with correct macaroon path for custom sovereign datadir
alias lncli_s='~/bin/lncli_sovereign'

# runit sv without needing SVDIR prefix
export SVDIR="$HOME/.config/runit/sv"

# Quick service management
alias sv_lnd='SVDIR=$HOME/.config/runit/sv sv'

# Start runsvdir if not already running (safe to call multiple times)
sovereign_start_runit() {
    if ! pgrep -f "runsvdir.*runit/sv" >/dev/null 2>&1; then
        runsvdir -P "$HOME/.config/runit/sv" &
        echo "runsvdir started (PID $!)"
    else
        echo "runsvdir already running"
    fi
}
# === end MIKAYA-SOVEREIGN aliases ===
EOF
    echo "Aliases added to $BASHRC"
fi

# ─── 3. Verify ────────────────────────────────────────────────────
echo ""
echo "=== Install complete ==="
echo ""
echo "Run in current shell:  source ~/.bashrc"
echo ""
echo "Then use:"
echo "  lncli_s newaddress p2wkh    ← get Bitcoin funding address"
echo "  lncli_s getinfo             ← node pubkey + sync status"
echo "  lncli_s walletbalance       ← on-chain balance"
echo ""
echo "Service management:"
echo "  sovereign_start_runit       ← start runit supervisor (new sessions)"
echo "  sv_lnd start lnd            ← start LND"
echo "  sv_lnd status lnd           ← check LND status"
