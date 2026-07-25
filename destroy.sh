#!/usr/bin/env bash
# Retired: Destroy is no longer the default Stack teardown (ADR-0016).
# Use Park (keep Durables) or Teardown (full wipe including Durables).
set -euo pipefail

cat >&2 <<'EOF'
FAIL: destroy.sh no longer full-wipes the Stack.

  Park (everyday; keep Reserved IP + Host Volume):  ./park.sh
  Teardown (explicit full wipe including Durables): ./teardown.sh

Do not use a bare terraform destroy against Durables — without the unlock
(teardown.sh writes the override and passes allow_durable_destroy) it fails closed.
EOF
exit 1
