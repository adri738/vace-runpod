#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
source tests/helpers.sh
source provision_minimax.sh
source mirror_minimax.sh

echo "-- mirror manifest agrees with provisioning manifest --"

assert_eq "same number of files" \
    "$(manifest_lines | grep -c .)" \
    "$(mirror_manifest_lines | grep -c .)"

assert_eq "same filenames" \
    "$(manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')"

assert_eq "same sizes" \
    "$(manifest_lines | awk -F'|' '{print $1 "=" $3}' | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | awk -F'|' '{print $1 "=" $2}' | sort | tr '\n' ' ')"

assert_eq "every sha256 is 64 hex characters" "0" \
    "$(mirror_manifest_lines | awk -F'|' 'length($3) != 64 || $3 !~ /^[0-9a-f]+$/' | grep -c .)"

finish
