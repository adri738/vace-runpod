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
#
# Each fixture must violate ONLY the guard it targets. That is why the
# broken-brace header below keeps "data_offsets" intact: a header of plain
# filler would be rejected by the data_offsets grep instead, leaving the
# brace guard untested and a no-op regression in it invisible.

header_bad='X"t":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}'
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

echo "-- sanitize_requirements --"

cat > "$TMP/req.txt" <<'REQ'
# a comment line
torch>=2.4.0
torchvision
torchaudio==2.4.0
torchsde
xformers
triton
sageattention
numpy<2
transformers==4.44.0
tokenizers
huggingface-hub
huggingface_hub>=0.24
hf-xet
pillow
accelerate
safetensors
nvidia-cublas-cu12==12.4.5.8
cuda-python
comfyui-frontend-package
imageio-ffmpeg
opencv-python-headless
scipy

REQ

sanitize_requirements "$TMP/req.txt" "$TMP/clean.txt"

kept_present() { grep -qxF "$1" "$TMP/clean.txt"; }
line_absent()  { ! grep -qiE "^[[:space:]]*$1([<>=!~[]|[[:space:]]*$)" "$TMP/clean.txt"; }

assert_ok   "keeps torchsde"                kept_present "torchsde"
assert_ok   "keeps imageio-ffmpeg"          kept_present "imageio-ffmpeg"
assert_ok   "keeps opencv-python-headless"  kept_present "opencv-python-headless"
assert_ok   "keeps scipy"                   kept_present "scipy"
assert_ok   "keeps comments"                kept_present "# a comment line"

assert_ok   "drops torch"                   line_absent "torch"
assert_ok   "drops torchvision"             line_absent "torchvision"
assert_ok   "drops torchaudio"              line_absent "torchaudio"
assert_ok   "drops xformers"                line_absent "xformers"
assert_ok   "drops triton"                  line_absent "triton"
assert_ok   "drops sageattention"           line_absent "sageattention"
assert_ok   "drops numpy"                   line_absent "numpy"
assert_ok   "drops transformers"            line_absent "transformers"
assert_ok   "drops tokenizers"              line_absent "tokenizers"
assert_ok   "drops huggingface-hub"         line_absent "huggingface-hub"
assert_ok   "drops huggingface_hub"         line_absent "huggingface_hub"
assert_ok   "drops hf-xet"                  line_absent "hf-xet"
assert_ok   "drops pillow"                  line_absent "pillow"
assert_ok   "drops accelerate"              line_absent "accelerate"
assert_ok   "drops safetensors"             line_absent "safetensors"
assert_ok   "drops nvidia-* wheels"         line_absent "nvidia-cublas-cu12"
assert_ok   "drops cuda-python"             line_absent "cuda-python"
assert_ok   "drops comfyui-frontend-package" line_absent "comfyui-frontend-package"

# An all-blocked file must produce an empty result, not an error.
printf 'torch\nnumpy\n' > "$TMP/allblocked.txt"
sanitize_requirements "$TMP/allblocked.txt" "$TMP/allblocked.out"
assert_eq "all-blocked file yields no lines" "0" "$(grep -c . "$TMP/allblocked.out")"

echo "-- model manifest --"

assert_eq "manifest has 10 entries" "10" "$(manifest_lines | grep -c .)"

assert_eq "manifest totals 83169189972 bytes" "83169189972" \
    "$(manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"

assert_eq "no duplicate filenames" "0" \
    "$(manifest_lines | cut -d'|' -f1 | sort | uniq -d | grep -c .)"

assert_eq "every line has three fields" "0" \
    "$(manifest_lines | awk -F'|' 'NF != 3' | grep -c .)"

assert_eq "every size is a positive integer" "0" \
    "$(manifest_lines | awk -F'|' '$3 !~ /^[1-9][0-9]*$/' | grep -c .)"

assert_eq "every subdir is a known ComfyUI models folder" "0" \
    "$(manifest_lines | awk -F'|' '
        $2 != "text_encoders" && $2 != "diffusion_models" && $2 != "vae" &&
        $2 != "checkpoints" && $2 != "loras" && $2 != "vae_approx" &&
        $2 != "latent_upscale_models"' | grep -c .)"

assert_eq "text encoder is present at its exact size" "27141342152" \
    "$(manifest_lines | awk -F'|' '$1 == "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" {print $3}')"

assert_eq "reference-to-video model is present" "1" \
    "$(manifest_lines | grep -c '^minimax_h3_ref2va_pruned_int8_convrot\.safetensors|diffusion_models|')"

finish
