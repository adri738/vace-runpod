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

assert_eq "manifest has 14 entries" "14" "$(manifest_lines | grep -c .)"

assert_eq "10 base entries" "10" \
    "$(manifest_lines | awk -F'|' '$4 == "base"' | grep -c .)"

assert_eq "4 controlnet entries" "4" \
    "$(manifest_lines | awk -F'|' '$4 == "controlnet"' | grep -c .)"

assert_eq "base group totals 83169189972 bytes" "83169189972" \
    "$(manifest_lines | awk -F'|' '$4 == "base" {s += $3} END {printf "%d", s}')"

assert_eq "manifest totals 89084560623 bytes" "89084560623" \
    "$(manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"

assert_eq "no duplicate filenames" "0" \
    "$(manifest_lines | cut -d'|' -f1 | sort | uniq -d | grep -c .)"

assert_eq "every line has four fields" "0" \
    "$(manifest_lines | awk -F'|' 'NF != 4' | grep -c .)"

assert_eq "every size is a positive integer" "0" \
    "$(manifest_lines | awk -F'|' '$3 !~ /^[1-9][0-9]*$/' | grep -c .)"

assert_eq "every group is base or controlnet" "0" \
    "$(manifest_lines | awk -F'|' '$4 != "base" && $4 != "controlnet"' | grep -c .)"

assert_eq "every destination is an allowed folder" "0" \
    "$(manifest_lines | awk -F'|' '
        $2 != "models/text_encoders" && $2 != "models/diffusion_models" &&
        $2 != "models/vae" && $2 != "models/checkpoints" &&
        $2 != "models/loras" && $2 != "models/vae_approx" &&
        $2 != "models/latent_upscale_models" && $2 != "models/controlnet" &&
        $2 !~ /^custom_nodes\/comfyui_controlnet_aux\/ckpts\/[^\/]+\/[^\/]+$/' | grep -c .)"

assert_eq "base files never leave models/" "0" \
    "$(manifest_lines | awk -F'|' '$4 == "base" && $2 !~ /^models\//' | grep -c .)"

assert_eq "text encoder is present at its exact size" "27141342152" \
    "$(manifest_lines | awk -F'|' '$1 == "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" {print $3}')"

assert_eq "reference-to-video model is present" "1" \
    "$(manifest_lines | grep -c '^minimax_h3_ref2va_pruned_int8_convrot\.safetensors|models/diffusion_models|')"

assert_eq "controlnet model goes where the FunControl loader looks" "models/controlnet" \
    "$(manifest_lines | awk -F'|' '$1 == "minimax_h3_fun_controlnet_union_pruned_bf16.safetensors" {print $2}')"

echo "-- group selection --"

# active_count_with <value|__unset__> <lister> — runs the lister in a
# subshell with MINIMAX_CONTROLNET set (or unset), so no assertion can leak
# the variable into the next one.
active_count_with() {
    (
        if [[ "$1" == "__unset__" ]]; then
            unset MINIMAX_CONTROLNET
        else
            export MINIMAX_CONTROLNET="$1"
        fi
        "$2" | grep -c .
    )
}

assert_eq "unset -> base only"           "10" "$(active_count_with __unset__ active_manifest_lines)"
assert_eq "false -> base only"           "10" "$(active_count_with false active_manifest_lines)"
assert_eq "empty -> base only"           "10" "$(active_count_with '' active_manifest_lines)"
assert_eq "misspelt 'ture' -> base only" "10" "$(active_count_with ture active_manifest_lines)"
assert_eq "true -> all 14"               "14" "$(active_count_with true active_manifest_lines)"
assert_eq "TRUE -> all 14"               "14" "$(active_count_with TRUE active_manifest_lines)"
assert_eq "1 -> all 14"                  "14" "$(active_count_with 1 active_manifest_lines)"
assert_eq "yes -> all 14"                "14" "$(active_count_with yes active_manifest_lines)"

assert_eq "active lines drop the group field" "0" \
    "$( (export MINIMAX_CONTROLNET=true; active_manifest_lines) | awk -F'|' 'NF != 3' | grep -c .)"

assert_eq "base template never receives a controlnet file" "0" \
    "$( (export MINIMAX_CONTROLNET=false; active_manifest_lines) \
        | grep -cE '\.(onnx|pt|pth)\||fun_controlnet|/ckpts/')"

echo "-- workflows --"

assert_eq "two workflows" "2" "$(workflow_lines | grep -c .)"

assert_eq "main workflow is base" "MINIMAX_H3_ULTRA_WORKFLOW-V3.json|base" \
    "$(workflow_lines | grep '^MINIMAX_H3_ULTRA_WORKFLOW-V3\.json|')"

assert_eq "ControlNet workflow is controlnet" \
    "MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json|controlnet" \
    "$(workflow_lines | grep '_CONTROLNET\.json|')"

assert_eq "base template gets only the main workflow" \
    "MINIMAX_H3_ULTRA_WORKFLOW-V3.json" \
    "$( (export MINIMAX_CONTROLNET=false; active_workflow_lines) )"

assert_eq "ControlNet template gets both workflows" "2" \
    "$(active_count_with true active_workflow_lines)"

echo "-- model_ok --"

make_safetensors "$TMP/ok.safetensors"
assert_ok "safetensors: valid at its size" model_ok "$TMP/ok.safetensors" 66

# Right size, but not a safetensors file. A size-only check would accept it,
# so rejecting it proves model_ok really hands .safetensors files to the
# header check instead of stopping at the size.
printf 'not a safetensors file, only text' > "$TMP/fake.safetensors"
assert_fail "safetensors: right size, no valid header" \
    model_ok "$TMP/fake.safetensors" "$(stat -c%s "$TMP/fake.safetensors")"

printf 'ONNXDATA%.0s' {1..10} > "$TMP/model.onnx"
assert_ok   "onnx: exact size is enough"      model_ok "$TMP/model.onnx" 80
assert_fail "onnx: wrong size is rejected"    model_ok "$TMP/model.onnx" 81

head -c 50 "$TMP/model.onnx" > "$TMP/cut.pt"
assert_fail "pt: truncated download rejected" model_ok "$TMP/cut.pt" 80

assert_fail "pth: missing file rejected"      model_ok "$TMP/absent.pth" 80

finish
