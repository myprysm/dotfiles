#!/bin/bash
# PROTOTYPE STUB (wayfinder #7) — vault-first drift audit (issue #11 §4).
# Compares local ~/.ssh public-key fingerprints + tracked file list against
# vault item names (bw/op CLIs). Values never touched. Reports:
#   - local-only items (unbacked — violates vault-first)
#   - vault-only items (not restored here — may be intentional)
# Nags when the last local backup archive is older than 30 days.
set -eu
echo "TODO (#11 §4)"
exit 1
