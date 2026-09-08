#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
source tests/helpers.sh
source provision_minimax.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "-- safetensors_ok --"

make_safetensors "$TMP/good.safetensors"
assert_ok   "valid file with matching size"      safetensors_ok "$TMP/good.safetensors" 66
assert_fail "valid file with wrong size"         safetensors_ok "$TMP/good.safetensors" 67

head -c 40 "$TMP/good.safetensors" > "$TMP/trunc.safetensors"
assert_fail "truncated download"                 safetensors_ok "$TMP/trunc.safetensors" 66

printf '<html><body>404 Not Found</body></html>' > "$TMP/html.safetensors"
assert_fail "HTML error page saved as a model"   safetensors_ok "$TMP/html.safetensors" 39

: > "$TMP/empty.safetensors"
assert_fail "zero-byte file"                     safetensors_ok "$TMP/empty.safetensors" 0

assert_fail "missing file"                       safetensors_ok "$TMP/nope.safetensors" 66

# The two cases below matter more than they look. Every case above is
# rejected by the size check or the header-length bounds, so none of them
# ever forces the last two guards to reject anything. Without these, both
# guards could be silently turned into no-ops and the suite would stay
# green. Each passes its own file size to safetensors_ok so that the size
# check cannot be what does the rejecting.

header_bad='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
: > "$TMP/nobrace.safetensors"
write_u64le "${#header_bad}" "$TMP/nobrace.safetensors"
printf '%s' "$header_bad" >> "$TMP/nobrace.safetensors"
printf 'ABCD' >> "$TMP/nobrace.safetensors"
assert_fail "header does not start with a brace" \
    safetensors_ok "$TMP/nobrace.safetensors" "$(stat -c%s "$TMP/nobrace.safetensors")"

header_nooffsets='{"t":{"dtype":"F16","shape":[2],"no_offsets":[0,4]}}'
: > "$TMP/nooffsets.safetensors"
write_u64le "${#header_nooffsets}" "$TMP/nooffsets.safetensors"
printf '%s' "$header_nooffsets" >> "$TMP/nooffsets.safetensors"
printf 'ABCD' >> "$TMP/nooffsets.safetensors"
assert_fail "header without data_offsets" \
    safetensors_ok "$TMP/nooffsets.safetensors" "$(stat -c%s "$TMP/nooffsets.safetensors")"

finish
