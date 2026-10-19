#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN lncli wrapper
# ═══════════════════════════════════════════════════════════════════
#
# INSTALL (one time):
#   cp lncli_sovereign.sh ~/bin/lncli_sovereign
#   chmod +x ~/bin/lncli_sovereign
#   alias lncli_s='~/bin/lncli_sovereign'
#
# WHY: lnd.conf uses a custom datadir so lncli can't find macaroons
# by default. This wrapper bakes in the correct paths.
# ═══════════════════════════════════════════════════════════════════

MACAROON="$HOME/sovereign/lnd/data/chain/bitcoin/mainnet/admin.macaroon"

# Discover tls.cert at runtime — handles any lnddir location
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

if [ ! -f "$MACAROON" ]; then
    echo "[SOVEREIGN-LNCLI] ERROR: macaroon not found: $MACAROON"
    echo "  Is LND running and wallet unlocked?"
    exit 1
fi
if [ -z "$TLSCERT" ]; then
    echo "[SOVEREIGN-LNCLI] ERROR: tls.cert not found anywhere under $HOME"
    echo "  Is LND running? Try: find ~ -name tls.cert 2>/dev/null"
    exit 1
fi

exec lncli \
    --macaroonpath "$MACAROON" \
    --tlscertpath  "$TLSCERT" \
    "$@"
