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

echo "-- interrupt --"

# What this fix is really about is INT: hf catches Ctrl+C and returns
# normally, so without a trap bash never stops. That exact situation cannot
# be replayed here — bash starts background jobs with SIGINT ignored, and a
# signal ignored on entry cannot be trapped. So INT coverage is pinned by
# reading the trap's signal list, and the stopping behaviour is proven with
# TERM, which the same trap handles identically.
assert_eq "main traps both INT and TERM" "1" \
    "$(sed -n '/^main() {/,/^}/p' mirror_minimax.sh | grep -cE '^[[:space:]]*trap .* INT TERM$')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
calls="$TMP/calls.log"
: > "$calls"

(
    require_tools()    { return 0; }
    hf()               { return 0; }
    copy_one()         { echo "copy $1" >> "$calls"; sleep 2; }
    upload_workflows() { echo "workflows" >> "$calls"; }
    export HF_WRITE_TOKEN=test-only
    WORK="$TMP/work"
    main
) > "$TMP/out.log" 2>&1 &
run_pid=$!

# Wait until the first file is being copied, so the signal lands mid-run
# rather than racing process start-up, which is slow on Windows.
for _ in $(seq 1 100); do
    grep -q '^copy ' "$calls" && break
    sleep 0.1
done
kill -TERM "$run_pid"
wait "$run_pid"
run_status=$?

# 130 comes only from the trap. Without it, TERM's default action kills the
# shell outright and the status is 143 — which is also why the two counts
# below pass either way: they guard against a trap that forgets to exit.
assert_eq "interrupted run exits 130, via the trap" "130" "$run_status"

assert_eq "no further file starts after the interrupt" "1" \
    "$(grep -c '^copy ' "$calls")"

assert_eq "workflows are not uploaded after the interrupt" "0" \
    "$(grep -c '^workflows' "$calls")"

assert_eq "the stop is announced" "1" \
    "$(grep -c 'interrupted' "$TMP/out.log")"

echo "-- default mirror repo --"

# The mirror lives on a dedicated HuggingFace account, adri73782 — not the
# GitHub name adri738 the first draft assumed. Each script carries the
# default on its own, since each is fetched standalone, so both are pinned
# here to the same value. Sourced in a subshell with MINIMAX_HF_REPO unset
# so that the default, not an inherited override, is what gets read.
default_repo_of() { ( unset MINIMAX_HF_REPO; source "$1"; printf '%s' "$MIRROR_REPO" ); }

assert_eq "provisioning defaults to the dedicated mirror account" \
    "adri73782/minimax-h3-ultra-v3" "$(default_repo_of provision_minimax.sh)"

assert_eq "mirror defaults to the dedicated mirror account" \
    "adri73782/minimax-h3-ultra-v3" "$(default_repo_of mirror_minimax.sh)"

finish
