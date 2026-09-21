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

echo "-- mirror sources --"

assert_eq "every mirror line has five fields" "0" \
    "$(mirror_manifest_lines | awk -F'|' 'NF != 5' | grep -c .)"

assert_eq "every source repo is owner/name" "0" \
    "$(mirror_manifest_lines | awk -F'|' '$4 !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/' | grep -c .)"

assert_eq "every source path ends in its own filename" "0" \
    "$(mirror_manifest_lines | awk -F'|' '{n = split($5, p, "/"); if (p[n] != $1) print}' | grep -c .)"

# The base group is exactly the set that comes from the creator's repo; the
# ControlNet files all come from elsewhere. A row filed under the wrong
# source would still download fine from some public repo and never be
# noticed, so the two sets are pinned against each other.
assert_eq "base files are exactly those sourced from Aitrepreneur/FLX" \
    "$(manifest_lines | awk -F'|' '$4 == "base" {print $1}' | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | awk -F'|' '$4 == "Aitrepreneur/FLX" {print $1}' | sort | tr '\n' ' ')"

echo "-- workflows --"

# The workflow filenames are duplicated between the two scripts for the same
# reason the manifest is: each script is fetched standalone. This assertion is
# what keeps the duplicate honest. One of these names has already gone stale
# once, so it is not a hypothetical. provision_minimax.sh tags each name with
# its group while the mirror carries every workflow, so only names compare.
assert_eq "same workflow filenames" \
    "$(workflow_lines | cut -d'|' -f1 | sort | tr '\n' ' ')" \
    "$(mirror_workflow_lines | sort | tr '\n' ' ')"

finish
