#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# MIKAYA-SOVEREIGN Public Tunnel
# ═══════════════════════════════════════════════════════════════════
#
# Runs a Cloudflare quick tunnel exposing the L402 gateway (:8443)
# to the public internet through carrier CGNAT. Writes the current
# public URL to ~/sovereign/logs/tunnel_url.txt on every start.
#
# NOTE: Quick tunnels get a NEW random URL each restart. Read the
# current one with:  cat ~/sovereign/logs/tunnel_url.txt
#
# Run under runit — see install_all_sovereign_services.sh
# ═══════════════════════════════════════════════════════════════════

LOG_DIR="$HOME/sovereign/logs"
URL_FILE="$LOG_DIR/tunnel_url.txt"
GATEWAY="http://localhost:8443"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TUNNEL] $*"; }

if ! command -v cloudflared >/dev/null 2>&1; then
    log "ERROR: cloudflared not installed. Fix: pkg install cloudflared -y"
    sleep 60   # don't let runit spin-loop on a missing binary
    exit 1
fi

# Stale URL from a previous run is worse than no URL
rm -f "$URL_FILE"
log "Starting Cloudflare quick tunnel → $GATEWAY"

cloudflared tunnel --url "$GATEWAY" 2>&1 | while IFS= read -r line; do
    echo "$line"
    if [ ! -f "$URL_FILE" ]; then
        u=$(printf '%s' "$line" | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
        if [ -n "$u" ]; then
            printf '%s\n' "$u" > "$URL_FILE"
            log "PUBLIC URL: $u  (saved to $URL_FILE)"
        fi
    fi
done
