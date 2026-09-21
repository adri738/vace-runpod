#!/usr/bin/env bash
# Runs every test file. Exits non-zero if any of them fails.
cd "$(dirname "$0")/.." || exit 1

status=0
for t in tests/test_*.sh; do
    printf '\n=== %s ===\n' "$t"
    bash "$t" || status=1
done

if [[ "$status" -eq 0 ]]; then
    printf '\nALL TESTS PASSED\n'
else
    printf '\nSOME TESTS FAILED\n'
fi
exit "$status"
