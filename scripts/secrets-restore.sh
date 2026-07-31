#!/bin/bash
# PROTOTYPE STUB (wayfinder #7) — restore vaulted secrets onto THIS machine.
# Explicit invocation only; never wired into chezmoi apply (issue #11 §5):
# a throwaway VM running the bootstrap one-liner must not implicitly receive keys.
set -eu
echo "TODO (#11 §5):"
echo "  - pull SSH private keys + ~/.ssh/config from bw (personal) / op (work)"
echo "  - gpg --import armor export + ownertrust"
echo "  - place Ansible Vault password files"
echo "  - chmod 600 keys / 700 ~/.ssh"
exit 1
