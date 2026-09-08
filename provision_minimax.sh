#!/usr/bin/env bash
# provision_minimax.sh — MiniMax H3 Ultra V3 provisioning for RunPod.
#
# Runs on every boot via the Container Start Command. Idempotent: every
# phase skips work that is already done. Never aborts on the first error —
# problems accumulate in FAILED and are reported in a final summary.
#
# Usage:
#   bash provision_minimax.sh          # manual run from a Jupyter terminal
#   bash provision_minimax.sh --boot   # boot mode: waits for ComfyUI first
#
# Design note: every side effect lives inside a function so that the test
# suite can source this file without touching the machine.

set -uo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
MIRROR_REPO="${MINIMAX_HF_REPO:-adri738/minimax-h3-ultra-v3}"
LOG="${MINIMAX_LOG:-/workspace/provision_minimax.log}"
STAGING="${MINIMAX_STAGING:-/workspace/.minimax_staging}"
MODEL_PARALLEL="${MINIMAX_PARALLEL:-3}"

FAILED=()

log() { printf '%s\n' "$*"; }

# safetensors_ok <file> <expected_bytes>
#
# The exact byte size of every model is known from the HuggingFace tree API
# and baked into MODEL_MANIFEST, so an exact size match already rules out
# every truncated download. The header parse additionally rejects files that
# are the right size but not safetensors at all (an HTML error page, say).
safetensors_ok() {
    local file="$1" expected="$2"
    local actual header_len first

    [[ -f "$file" ]] || return 1

    actual="$(stat -c%s "$file" 2>/dev/null)" || return 1
    [[ "$actual" == "$expected" ]] || return 1

    header_len="$(head -c 8 "$file" | od -An -tu8 | tr -d '[:space:]')"
    [[ "$header_len" =~ ^[0-9]+$ ]] || return 1
    (( header_len > 2 && header_len < 104857600 )) || return 1
    (( 8 + header_len <= actual )) || return 1

    first="$(head -c 9 "$file" | tail -c 1)"
    [[ "$first" == "{" ]] || return 1

    head -c "$(( 8 + header_len ))" "$file" | tail -c "$header_len" \
        | grep -q '"data_offsets"'
}

# sanitize_requirements <input> <output>
#
# Strips packages that belong to the image's GPU runtime. A custom node
# pinning "torch==2.3" would silently replace the CUDA 13 build and break
# every GPU operation on the pod. The name alternation is anchored so that
# "torch" is dropped while "torchsde" — a real, unrelated dependency — is
# kept. The nvidia-/cuda- families need their own prefix branch because
# their real names carry suffixes (nvidia-cublas-cu12).
sanitize_requirements() {
    local input="$1" output="$2"

    grep -Eiv \
        '^[[:space:]]*((torch|torchvision|torchaudio|xformers|triton|sageattention|numpy|transformers|tokenizers|huggingface[-_]hub|hf[-_]xet|pillow|accelerate|safetensors|comfyui[-_]frontend[-_]package|comfyui[-_]workflow[-_]templates|comfyui[-_]embedded[-_]docs)|(nvidia|cuda)[-_][A-Za-z0-9._-]*)([[:space:]]*[<>=!~[].*)?[[:space:]]*$' \
        "$input" > "$output" || true
}

main() {
    log "provision_minimax.sh: no phases implemented yet"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
