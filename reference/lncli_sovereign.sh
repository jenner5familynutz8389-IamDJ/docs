#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN lncli wrapper
# ═══════════════════════════════════════════════════════════════════
#
# INSTALL (one time):
#   cp lncli_sovereign.sh ~/bin/lncli_sovereign
#   chmod +x ~/bin/lncli_sovereign
#   # Then add to ~/.bashrc:
#   alias lncli_s='~/bin/lncli_sovereign'
#
# OR for a seamless drop-in (replaces bare lncli in current shell):
#   alias lncli='~/bin/lncli_sovereign'
#
# WHY:
#   lnd.conf sets datadir=~/sovereign/lnd/data (custom path for
#   SD-card sovereignty / eMMC separation).  lncli defaults to
#   ~/.lnd/ and fails to find the macaroon.  This wrapper bakes in
#   the correct --macaroonpath so every subcommand just works.
#
# USAGE — identical to lncli:
#   lncli_sovereign newaddress p2wkh
#   lncli_sovereign getinfo
#   lncli_sovereign walletbalance
#   lncli_sovereign listchannels
#   lncli_sovereign addinvoice --amt 100
# ═══════════════════════════════════════════════════════════════════

MACAROON="$HOME/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
TLSCERT="$HOME/sovereign/lnd/data/tls.cert"

if [ ! -f "$MACAROON" ]; then
    echo "[SOVEREIGN-LNCLI] ERROR: macaroon not found at $MACAROON"
    echo "  Is LND running and wallet unlocked?"
    exit 1
fi

exec lncli \
    --macaroonpath "$MACAROON" \
    --tlscertpath "$TLSCERT" \
    "$@"
