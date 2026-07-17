# MIKAYA-SOVEREIGN Device Migration

Moving the sovereign node to a new Android device — written for the
**Motorola G Power 5G 2023 (Dimensity 930, Android 14)**, works for any
arm64 Android with Termux.

The node's identity — the pubkey every ledger anchor verifies against —
lives in the LND wallet. Migrate the wallet and the new device IS the
same sovereign node. All previously issued anchor signatures stay valid.

---

## ⚠️ The one rule that protects your funds

**Never run the same wallet on two devices at the same time.**
Stop LND on the old device before starting it on the new one. With
channels open, running twice can broadcast outdated states and forfeit
funds. Right now (zero channels) is the safest moment to migrate.

---

## Phase 1 — New device: apps

1. Install **F-Droid** (f-droid.org) — Termux from Play Store is broken.
2. From F-Droid install **Termux** and **Termux:Boot**.
3. Open Termux:Boot once (it just needs one launch to register).
4. Android Settings → Apps → Termux → Battery → **Unrestricted**.
   Motorola/Android 14 kills background apps aggressively; also disable
   "Adaptive Battery" optimizations for Termux and Termux:Boot.

## Phase 2 — New device: bootstrap

Paste into Termux:

```bash
curl -sL https://raw.githubusercontent.com/jenner5familynutz8389-IamDJ/docs/claude/sovereign-core-2026-i1djxz/reference/sovereign_bootstrap.sh | bash
```

Installs every package (git, python, lnd, runit, cloudflared, curl,
util-linux), clones this repo, writes lnd.conf, builds the directory
tree. CPU note: the Dimensity 930 enumerates its six Cortex-A55
efficiency cores as cpu0–5, so the `taskset -c 2-5` pinning used by all
services carries over from the F110 Pro unchanged.

## Phase 3 — Old device: back up the wallet

```bash
# 1. STOP EVERYTHING (the one rule)
SVDIR=~/.config/runit/sv sv stop lnd authority-engine auto-channel tunnel 2>/dev/null
pkill -f "runsvdir|lnd|authority_engine|auto_channel|cloudflared" 2>/dev/null
sleep 5; pgrep -af lnd && echo "STILL RUNNING — do not proceed" || echo "clear"

# 2. Package wallet + credentials + config
tar czf /sdcard/Download/sovereign_wallet_backup.tar.gz \
    -C "$HOME" \
    sovereign/lnd/data \
    .lnd/lnd.conf \
    .config/sovereign/wallet.pw
echo "backup at /sdcard/Download/sovereign_wallet_backup.tar.gz"
```

(`tar` needs storage access — run `termux-setup-storage` first if it
errors.) Transfer the file to the new phone's Download folder by any
means: Quick Share, USB, SD card.

## Phase 4 — New device: restore

```bash
# Extract over the skeleton the bootstrap created
tar xzf /sdcard/Download/sovereign_wallet_backup.tar.gz -C "$HOME"
chmod 600 ~/.config/sovereign/wallet.pw
ls ~/sovereign/lnd/data/chain/bitcoin/mainnet/wallet.db && echo "wallet restored"
```

tls.cert is NOT copied on purpose — LND generates a fresh one on first
start, and every script discovers it at runtime.

### Alternative: seed restore (no file transfer)

If you have the 24-word aezeed written down, skip Phases 3–4:

```bash
lnd &   # wait ~20s
lncli --tlscertpath ~/.lnd/tls.cert create
# → new password, answer "y" to existing seed, type the 24 words
printf '%s' 'THE_PASSWORD' > ~/.config/sovereign/wallet.pw
chmod 600 ~/.config/sovereign/wallet.pw
pkill lnd
```

Same seed ⇒ same identity pubkey ⇒ old anchors still verify.

## Phase 5 — New device: deploy the full stack

```bash
bash ~/sovereign/docs/reference/sovereign_deploy.sh
```

One shot: syncs repo, installs all runit services (lnd,
authority-engine, auto-channel, auto-unlock, tunnel), starts the stack,
auto-unlocks the wallet, waits for L402 to go live, prints the public
tunnel URL. Neutrino header sync on first run takes 30–90 min on a
fresh datadir; the wallet-file copy in Phase 4 carries the synced chain
data with it, so a full restore resumes near the tip.

## Phase 6 — Verify (the telemetry)

```bash
# Full diagnostics: node status, PIDs, wallet, sync height, credentials
curl -s http://127.0.0.1:8443/status

# Identity check — pubkey must match the old device
~/bin/lncli_sovereign getinfo | grep identity_pubkey
# expected: 0318d505bb18d140c3d13c02246cf73e59a82c256c52e3fe1b781d53cebc777f1f

# L402 live
curl -s http://127.0.0.1:8443/query | grep invoice

# Anchor signing
curl -s -X POST http://127.0.0.1:8443/anchor \
  -H "Content-Type: application/json" -d '{"hash":"test","ref":"migration-check"}'

# Public URL (give this to the manus.space store settings)
cat ~/sovereign/logs/tunnel_url.txt
```

All four good + pubkey matches ⇒ migration complete. Update the ASGS
store's anchor-gateway setting to the new tunnel URL, reboot the phone
once to confirm Termux:Boot brings the whole stack up unattended.

## Old device afterward

Leave LND stopped. To repurpose the old phone, delete the wallet so the
rule can never be broken by accident:

```bash
rm -rf ~/sovereign/lnd/data/chain
```
