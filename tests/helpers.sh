#!/usr/bin/env bash
# Minimal assertion harness. No dependencies beyond bash + coreutils,
# because the developer machine (Windows/Git Bash) has no python.

TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1"
}

# assert_ok "name" command...   -> command must succeed
assert_ok() {
    local name="$1"; shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

# assert_fail "name" command... -> command must fail
assert_fail() {
    local name="$1"; shift
    if "$@"; then fail "$name (expected failure, got success)"; else pass "$name"; fi
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name"
        printf '       expected: [%s]\n' "$expected"
        printf '       actual:   [%s]\n' "$actual"
    fi
}

# Append a little-endian uint64 to a file.
write_u64le() {
    local value="$1" file="$2" i byte
    for ((i = 0; i < 8; i++)); do
        byte=$(( (value >> (i * 8)) & 255 ))
        printf "\\x$(printf '%02x' "$byte")" >> "$file"
    done
}

# make_safetensors <path> [extra_trailing_bytes]
# Produces a structurally valid safetensors file of 66 bytes (+ extras).
make_safetensors() {
    local path="$1" extra="${2:-0}" i
    local header='{"t":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}'

    : > "$path"
    write_u64le "${#header}" "$path"
    printf '%s' "$header" >> "$path"
    printf 'ABCD' >> "$path"
    for ((i = 0; i < extra; i++)); do printf 'X' >> "$path"; done
}

finish() {
    printf '\n%d test(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
    [[ "$TESTS_FAILED" -eq 0 ]]
}
