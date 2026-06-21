# Reference archive

These files are inert reference copies of scripts the user is running on
their own Android device (Termux, FOSSiBOT F110 Pro). They are stored here
purely for archival/version-history purposes:

- Not executed anywhere in this repository or CI.
- Not wired into the Mintlify documentation site.
- Not modified beyond fixing transcription artifacts and redacting PII (see below).

## Files

- `sovereign_unified_v2026.06.py` — the current/authoritative main system
  file (supersedes the earlier `sovereign_core_final.py`, which has been
  removed from this archive). Real IMEI numbers, phone numbers (MSISDNs),
  and the T-Mobile account ID that were hardcoded in `LAYER8_DEVICES` /
  `TMOBILE_ACCOUNT_ID` in the original source have been replaced with
  `"REDACTED"` placeholders before committing, since this file persists in
  git history once pushed.
- `bigset_routes.py` — optional FastAPI router meant to be mounted onto the
  unified file via `include_router()`.
- `authority_ai_evaluator.py` — standalone polling service that bridges the
  Authority Engine to a local/remote AI model. Its `verify_l402_payment()`
  is a stub (accepts any hash ≥32 chars) and its main loop simulates a
  fake settled payment every 2 seconds rather than subscribing to real
  Authority Engine events — this is a demonstration scaffold, not a working
  payment verifier.
- `ai_bootstrap.py` — small bootstrap launcher referenced by
  `authority_ai_evaluator.py`'s fallback path.

## Note on L402 implementations

Three different L402 (Lightning HTTP 402) implementations exist across
these files, with different levels of completeness:

- `bigset_routes.py` and `sovereign_unified_v2026.06.py`'s `PaymentGate`
  talk to a real LND node (REST API and `lncli` respectively).
- `authority_ai_evaluator.py`'s `verify_l402_payment` is a placeholder stub.
