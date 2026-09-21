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

# model_ok <file> <expected_bytes>
#
# Not every model is safetensors: the ControlNet preprocessors ship as .pth,
# .onnx and .pt, which have no header to parse. For those the exact byte
# size — known ahead of time from the HuggingFace tree API and baked into
# MODEL_MANIFEST — is the whole check, and it still rejects every truncated
# download. .safetensors files get the stricter safetensors_ok, header
# included, so an HTML error page of the right size cannot slip through.
model_ok() {
    local file="$1" expected="$2" actual

    case "$file" in
        *.safetensors)
            safetensors_ok "$file" "$expected"
            return
            ;;
    esac

    [[ -f "$file" ]] || return 1
    actual="$(stat -c%s "$file" 2>/dev/null)" || return 1
    [[ "$actual" == "$expected" ]]
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

# filename|destination relative to COMFY_ROOT|exact size in bytes|group
#
# Sizes read from the HuggingFace tree API (base 2026-09-08, controlnet
# 2026-09-21). They are the contract model_ok checks each download against,
# so they must never be edited by hand — regenerate them from the API if the
# mirror content ever changes.
#
# Group "base" installs on both templates; "controlnet" only when
# MINIMAX_CONTROLNET is on. The controlnet destinations were read from the
# node sources, not guessed: the FunControl loader lists folder_paths
# category "controlnet", and comfyui_controlnet_aux reuses
# ckpts/<hf_repo_id>/<file> when it is already there instead of downloading.
MODEL_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|models/text_encoders|27141342152|base
minimax_h3_fl2va_pruned_int8_convrot.safetensors|models/diffusion_models|20970379616|base
minimax_h3_ref2va_pruned_int8_convrot.safetensors|models/diffusion_models|20970379616|base
minimax_h3_t1_image_vae_step1597.safetensors|models/vae|5207808784|base
minimax_h3_video_vae_fp16.safetensors|models/vae|5207808496|base
sam3.1_multiplex_fp16.safetensors|models/checkpoints|1745546848|base
minimax_h3_latent_upscaler_3d_fp16.safetensors|models/latent_upscale_models|690592672|base
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|models/loras|620285592|base
minimax_h3_audio_vae_fp32.safetensors|models/vae|605254808|base
taeh3.safetensors|models/vae_approx|9791388|base
minimax_h3_fun_controlnet_union_pruned_bf16.safetensors|models/controlnet|4222169456|controlnet
depth_anything_v2_vitl.pth|custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Large|1341395338|controlnet
yolox_l.onnx|custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose|216746733|controlnet
dw-ll_ucoco_384_bs5.torchscript.pt|custom_nodes/comfyui_controlnet_aux/ckpts/hr16/DWPose-TorchScript-BatchSize5|135059124|controlnet
'

# filename|group
WORKFLOW_FILES='
MINIMAX_H3_ULTRA_WORKFLOW-V3.json|base
MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json|controlnet
'

manifest_lines() {
    printf '%s\n' "$MODEL_MANIFEST" | grep -vE '^[[:space:]]*(#|$)'
}

workflow_lines() {
    printf '%s\n' "$WORKFLOW_FILES" | grep -vE '^[[:space:]]*(#|$)'
}

# controlnet_enabled — true when MINIMAX_CONTROLNET is true, 1 or yes, in any
# case. Everything else, unset or misspelt included, means base only: when
# in doubt the script installs the smaller set, never the larger one.
controlnet_enabled() {
    case "${MINIMAX_CONTROLNET:-}" in
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# in_active_group — filter for group-tagged lines on stdin, the group being
# the last |-separated field. Prints only the lines this template installs,
# with the group field removed, so every consumer sees one fixed shape
# whatever the tagging. Used for models, workflows and node packs alike.
# Plain sub() rather than NF surgery, so it behaves the same in gawk and
# mawk.
in_active_group() {
    local cn=0
    controlnet_enabled && cn=1
    awk -v cn="$cn" '
        {
            group = $0
            sub(/.*\|/, "", group)
            if (group == "base" || (cn == 1 && group == "controlnet")) {
                sub(/\|[^|]*$/, "")
                print
            }
        }'
}

active_manifest_lines() { manifest_lines | in_active_group; }
active_workflow_lines() { workflow_lines | in_active_group; }

main() {
    log "provision_minimax.sh: no phases implemented yet"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
