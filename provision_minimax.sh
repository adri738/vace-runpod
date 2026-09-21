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
MIRROR_REPO="${MINIMAX_HF_REPO:-adri73782/minimax-h3-ultra-v3}"
LOG="${MINIMAX_LOG:-/workspace/provision_minimax.log}"
STAGING="${MINIMAX_STAGING:-/workspace/.minimax_staging}"
MODEL_PARALLEL="${MINIMAX_PARALLEL:-3}"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

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

# Custom-node packs: directory|clone url|pinned commit|group.
#
# Kept identical to docs/minimax-node-pins.txt, which is the reviewable
# source of truth; tests/test_provision_minimax.sh fails if they drift.
# Ten of these point at forks under adri738 so a deleted upstream cannot
# break the template. Pinning protects against breaking changes; forking
# protects against deletion. Both are needed. The group field works as it
# does for models: "controlnet" packs install only when MINIMAX_CONTROLNET
# is on.
NODE_PACKS='
ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager.git|f82970b7cb63ad44928308f980a1d38fda103cbb|base
rgthree-comfy|https://github.com/rgthree/rgthree-comfy.git|2c5342a8cb0eaecaabf61435a5f37dd594c510ba|base
ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes.git|c9869eade9920a1b949de07c4a197156006bcceb|base
ComfyUI-VideoHelperSuite|https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git|4d907bee61e92c2e65af3bd6383a4e4d356126d1|base
ComfyUI-Spectrum-MiniMax-H3|https://github.com/adri738/ComfyUI-Spectrum-MiniMax-H3.git|a360f64fbfa54681ded100a64ded86a5713ddf17|base
ComfyUI-MiniMaxH3-Director|https://github.com/adri738/ComfyUI-MiniMaxH3-Director.git|84863236288ca387c291acffdbfee5b77d1a77a5|base
ComfyUI-Fantastic-MiniMaxH3-PromptBuilder|https://github.com/adri738/ComfyUI-Fantastic-MiniMaxH3-PromptBuilder.git|06fef6cd8767e2726c9250d6d67843859d58568c|base
ComfyUi-Scale-Image-to-Total-Pixels-Advanced|https://github.com/adri738/ComfyUi-Scale-Image-to-Total-Pixels-Advanced.git|79e831097bb7a76ade3a28359300e62332086c42|base
ComfyUI-MiniMaxH3-T1-Latent|https://github.com/adri738/ComfyUI-MiniMaxH3-T1-Latent.git|6f55b2932713029b1547f3def8ae4e5c60f4e6ee|base
ComfyUI-H3-Motion-Context-MultiRef|https://github.com/adri738/ComfyUI-H3-Motion-Context-MultiRef-V3.git|d299ea552d49213e25a337f6e2f24fbf64e78f40|base
MaskVidExperiments|https://github.com/adri738/MaskVidExperiments.git|e5f5a28c1d82e343cc43f6ac59529ab80a7e0ae2|base
ComfyUI-NKD-Basic-Tools|https://github.com/adri738/ComfyUI-NKD-Basic-Tools.git|86b9ae1b2217a5c19ce3329a66f51db9ddbb60bf|base
Comfyui_Minimax_h3_latent_Upscaler|https://github.com/adri738/Comfyui_Minimax_h3_latent_Upscaler.git|d7c01b9011f2e8439493f6c02c29995a27df276f|base
ComfyUI-H3-FunControl|https://github.com/adri738/ComfyUI-H3-FunControl.git|d2a3faa7e29f45b8cb03685368c1243f08143910|controlnet
comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git|59b1fc411ede8623b2997855b8018f0b3b6cf49f|controlnet
'

node_pack_lines() {
    printf '%s\n' "$NODE_PACKS" | grep -vE '^[[:space:]]*(#|$)'
}

active_node_pack_lines() { node_pack_lines | in_active_group; }

setup_logging() {
    mkdir -p "$(dirname "$LOG")" "$STAGING"
    exec > >(tee -a "$LOG") 2>&1
}

# find_comfy_python — prints ComfyUI's own interpreter, or fails.
#
# On runpod/comfyui:1.4.7-cuda13.0 the only venv is .venv-cu128 — a legacy
# name over a CUDA 13 torch (reconnaissance, 2026-09-21). There is no venv/
# or .venv/, so those alone would miss it. And there is deliberately no
# fallback to the system python3: pip-installing node requirements and
# SageAttention into the wrong interpreter would "succeed" silently and
# leave ComfyUI without them. Failing loudly is the safer outcome.
find_comfy_python() {
    local candidate
    for candidate in \
        "${COMFY_PYTHON:-}" \
        "$COMFY_ROOT/.venv-cu130/bin/python" \
        "$COMFY_ROOT/.venv-cu128/bin/python" \
        "$COMFY_ROOT"/.venv*/bin/python \
        "$COMFY_ROOT/venv/bin/python" \
        "$COMFY_ROOT/.venv/bin/python"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

phase0_wait_for_comfyui() {
    local waited=0
    local limit="${COMFY_WAIT_SECONDS:-1800}"

    log ""
    log "──── phase 0: waiting for ComfyUI ────"

    while [[ ! -d "$COMFY_ROOT/custom_nodes" ]]; do
        if (( waited >= limit )); then
            log "❌ ComfyUI never appeared at $COMFY_ROOT after ${limit}s"
            FAILED+=("phase 0: ComfyUI not found at $COMFY_ROOT")
            return 1
        fi
        sleep 10
        waited=$(( waited + 10 ))
    done

    if ! PYTHON="$(find_comfy_python)"; then
        log "❌ no ComfyUI virtualenv under $COMFY_ROOT — refusing to fall back to the system python"
        FAILED+=("phase 0: ComfyUI python not found")
        return 1
    fi
    log "ComfyUI root : $COMFY_ROOT (ready after ${waited}s)"
    log "ComfyUI python: $PYTHON"
}

# cuda_majors_match — true when nvcc and ComfyUI's torch target the same
# CUDA major version. torch's extension builder refuses a major mismatch, so
# without this check a future image bump could burn 15-30 min of pod time on
# every boot building a wheel that can never be produced. (On 1.4.7 both are
# 13 — see the spec's reconnaissance results.)
cuda_majors_match() {
    local nv tv
    nv="$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]*\)\..*/\1/p')"
    tv="$("$PYTHON" -c 'import torch; print((torch.version.cuda or "").split(".")[0])' 2>/dev/null)"
    [[ -n "$nv" && "$nv" == "$tv" ]]
}

# Name of the prebuilt SageAttention wheel in the mirror. It encodes the
# python, CUDA and torch versions, so a wheel built on one image is never
# installed onto an incompatible one.
sage_wheel_path() {
    local py cu tv
    py="$("$PYTHON" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null)" || return 1
    tv="$("$PYTHON" -c 'import torch; print(torch.__version__.split("+")[0])' 2>/dev/null)" || return 1
    cu="$("$PYTHON" -c 'import torch; print("cu" + torch.version.cuda.replace(".", ""))' 2>/dev/null)" || return 1
    printf 'wheels/sageattention-%s-%s-torch%s.whl\n' "$py" "$cu" "$tv"
}

phase1_sageattention() {
    local wheel_path wheel_local

    log ""
    log "──── phase 1: SageAttention ────"

    if "$PYTHON" -c 'import sageattention' 2>/dev/null; then
        log "• already importable — skip"
        return 0
    fi

    wheel_path="$(sage_wheel_path)" || wheel_path=""

    if [[ -n "$wheel_path" ]]; then
        wheel_local="$STAGING/$(basename "$wheel_path")"
        log "• looking for a prebuilt wheel: $wheel_path"
        if fetch_mirror_file "$wheel_path" "$wheel_local" \
            && "$PYTHON" -m pip install --no-input "$wheel_local"; then
            log "• installed SageAttention 2++ from the mirror ✔"
            rm -f "$wheel_local"
            return 0
        fi
        rm -f "$wheel_local"
        log "• no usable prebuilt wheel for this image"
    fi

    if "$PYTHON" -m pip install --no-input sageattention; then
        log "• installed SageAttention v1 from PyPI ✔"
    else
        log "• could not install SageAttention at all"
        FAILED+=("phase 1: no SageAttention")
    fi

    if command -v nvcc >/dev/null 2>&1 && cuda_majors_match; then
        log "• nvcc matches torch's CUDA — building SageAttention 2++ in the background"
        log "  (ComfyUI stays usable on v1 while this runs)"
        nohup bash "$SCRIPT_PATH" --build-sage >> "$LOG" 2>&1 </dev/null &
    else
        log "• no nvcc, or its CUDA major differs from torch's — staying on SageAttention v1"
    fi
}

# Runs in the background, once ever. Produces a wheel the user uploads to
# the mirror by hand, so the pod never needs a write token.
build_sage_wheel() {
    local src="$STAGING/SageAttention"
    local out="/workspace/wheels"
    local wheel_path wheel

    PYTHON="$(find_comfy_python)"
    wheel_path="$(sage_wheel_path)" || return 1

    log ""
    log "──── background: building SageAttention 2++ ────"

    rm -rf "$src"
    if ! git clone --depth 1 https://github.com/thu-ml/SageAttention.git "$src"; then
        log "❌ could not clone SageAttention"
        return 1
    fi

    mkdir -p "$out"
    if ! (cd "$src" && "$PYTHON" -m pip wheel . --no-deps --no-build-isolation --wheel-dir "$out"); then
        log "❌ SageAttention build failed — staying on v1"
        return 1
    fi

    wheel="$(ls -t "$out"/sageattention-*.whl 2>/dev/null | head -1)"
    if [[ -z "$wheel" ]]; then
        log "❌ build produced no wheel"
        return 1
    fi

    "$PYTHON" -m pip install --no-input --force-reinstall "$wheel" || true

    log ""
    log "✅ SageAttention 2++ built: $wheel"
    log "   ONE-TIME MANUAL STEP — upload it so every future pod skips this build:"
    log "     export HF_WRITE_TOKEN=hf_xxx"
    log "     HF_TOKEN=\$HF_WRITE_TOKEN hf upload $MIRROR_REPO $wheel $wheel_path"
    log "   Do this before terminating the pod; the wheel dies with the volume."
}

phase2_node_packs() {
    local dir url sha target current req tmp_req

    log ""
    log "──── phase 2: custom nodes ────"

    NODES_CHANGED=0
    mkdir -p "$COMFY_ROOT/custom_nodes"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue
        target="$COMFY_ROOT/custom_nodes/$dir"

        if [[ -d "$target/.git" ]]; then
            current="$(git -C "$target" rev-parse HEAD 2>/dev/null || true)"
            if [[ "$current" == "$sha" ]]; then
                log " [SKIP] $dir already at ${sha:0:8}"
                continue
            fi
        else
            rm -rf "$target"
            if ! git clone --filter=blob:none "$url" "$target"; then
                log " ❌ clone failed: $dir"
                FAILED+=("node clone: $dir")
                continue
            fi
            # A fresh clone has already replaced the pack on disk, even if
            # the checkout below then fails — so ComfyUI must restart.
            NODES_CHANGED=1
        fi

        git -C "$target" fetch --depth 1 origin "$sha" >/dev/null 2>&1 \
            || git -C "$target" fetch origin >/dev/null 2>&1 \
            || true

        if git -C "$target" checkout --detach "$sha" >/dev/null 2>&1; then
            log " • $dir → ${sha:0:8}"
            NODES_CHANGED=1
        else
            log " ❌ commit not found: $dir @ $sha"
            FAILED+=("node checkout: $dir")
        fi
    done <<< "$(active_node_pack_lines)"

    log ""
    log "──── phase 2b: safe node requirements ────"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue

        # The image manages these two itself; their requirements would only
        # fight with the runtime.
        if [[ "$dir" == "ComfyUI-Manager" || "$dir" == "ComfyUI-KJNodes" ]]; then
            log " [SKIP] $dir is managed by the image"
            continue
        fi

        req="$COMFY_ROOT/custom_nodes/$dir/requirements.txt"
        [[ -f "$req" ]] || { log " [SKIP] $dir has no requirements.txt"; continue; }

        tmp_req="$(mktemp)"
        sanitize_requirements "$req" "$tmp_req"

        if [[ ! -s "$tmp_req" ]]; then
            log " [SKIP] $dir needs nothing beyond the runtime"
            rm -f "$tmp_req"
            continue
        fi

        log " • installing requirements for $dir"
        if ! "$PYTHON" -m pip install --no-input --prefer-binary \
            --upgrade-strategy only-if-needed -r "$tmp_req"; then
            log " ⚠️  some optional requirements for $dir failed"
        fi
        rm -f "$tmp_req"
    done <<< "$(active_node_pack_lines)"

    # VideoHelperSuite needs this and it touches nothing GPU-related.
    "$PYTHON" -m pip install --no-input --prefer-binary imageio-ffmpeg >/dev/null 2>&1 \
        || FAILED+=("pip: imageio-ffmpeg")
}

# fetch_mirror_file <path in the mirror repo> <local output path>
#
# Tries the fastest transport first and degrades gracefully. Every
# transport carries the read-only token, because the mirror is private.
fetch_mirror_file() {
    local repo_path="$1" out="$2"
    local url="https://huggingface.co/${MIRROR_REPO}/resolve/main/${repo_path}"
    local hf_dir="$STAGING/hf/$(basename "$repo_path")"

    mkdir -p "$(dirname "$out")"

    if [[ -z "${HF_TOKEN:-}" ]]; then
        log "   ✗ HF_TOKEN is not set — the mirror is private and cannot be read"
        return 1
    fi

    if command -v hf >/dev/null 2>&1; then
        rm -rf "$hf_dir"
        if HF_TOKEN="$HF_TOKEN" hf download "$MIRROR_REPO" "$repo_path" \
            --local-dir "$hf_dir" >/dev/null 2>&1 \
            && mv -f "$hf_dir/$repo_path" "$out" 2>/dev/null; then
            rm -rf "$hf_dir"
            return 0
        fi
        rm -rf "$hf_dir"
    fi

    if command -v aria2c >/dev/null 2>&1; then
        if aria2c --continue=true --max-connection-per-server=16 --split=16 \
                  --min-split-size=8M --file-allocation=none \
                  --auto-file-renaming=false --allow-overwrite=true \
                  --max-tries=5 --retry-wait=3 --console-log-level=warn \
                  --header="Authorization: Bearer ${HF_TOKEN}" \
                  --dir="$(dirname "$out")" --out="$(basename "$out")" \
                  "$url"; then
            return 0
        fi
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -L --fail --retry 5 --retry-delay 3 --retry-all-errors \
                --connect-timeout 30 -C - \
                -H "Authorization: Bearer ${HF_TOKEN}" \
                -o "$out" "$url"; then
            return 0
        fi
    fi

    command -v wget >/dev/null 2>&1 && \
        wget --continue --tries=5 --timeout=120 \
             --header="Authorization: Bearer ${HF_TOKEN}" \
             -O "$out" "$url"
}

# download_model <filename> <dest dir relative to COMFY_ROOT> <bytes> <status dir>
#
# The destination is a full relative directory, not a models/ subfolder,
# because the ControlNet preprocessors live under custom_nodes/. Validation
# goes through model_ok, which handles the .pth/.onnx/.pt files that have no
# safetensors header.
download_model() {
    local name="$1" dest_rel="$2" bytes="$3" status="$4"
    local dest="$COMFY_ROOT/$dest_rel/$name"
    local stage="$STAGING/${name}.part"

    mkdir -p "$(dirname "$dest")"

    if model_ok "$dest" "$bytes"; then
        log " [SKIP] $name (already valid)"
        : > "$status/ok.$name"
        return 0
    fi

    if [[ -e "$dest" ]]; then
        log " [WARN] discarding incomplete $name"
        rm -f "$dest"
    fi

    log " • downloading $name"
    rm -f "$stage"

    if fetch_mirror_file "$name" "$stage" && model_ok "$stage" "$bytes"; then
        mv -f "$stage" "$dest"
        log "   ✓ $name"
        : > "$status/ok.$name"
        return 0
    fi

    rm -f "$stage"
    log "   ✗ FAILED $name"
    : > "$status/fail.$name"
    return 1
}

phase3_models() {
    local status name dest_rel bytes running=0 failures count total

    log ""
    log "──── phase 3: models ────"

    # Counted from the manifest rather than hardcoded: 10 files on the base
    # template, 14 with ControlNet.
    count="$(active_manifest_lines | grep -c .)"
    total="$(active_manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"
    log "$count files, $total bytes, ${MODEL_PARALLEL} at a time"

    status="$STAGING/status"
    rm -rf "$status"
    mkdir -p "$status"

    # Largest first across both groups, so the 25 GB text encoder starts at
    # once instead of queueing behind small files.
    local pids=()
    while IFS='|' read -r name dest_rel bytes; do
        [[ -n "$name" ]] || continue
        download_model "$name" "$dest_rel" "$bytes" "$status" &
        pids+=($!)
        running=$(( running + 1 ))
        if (( running >= MODEL_PARALLEL )); then
            wait -n 2>/dev/null || true
            running=$(( running - 1 ))
        fi
    done <<< "$(active_manifest_lines | sort -t'|' -k3,3nr)"

    # Wait only for download jobs — bare 'wait' would also block on the
    # tee process from setup_logging (bash 5 tracks process-substitution
    # children), causing a deadlock.
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    failures="$(find "$status" -name 'fail.*' | wc -l | tr -d ' ')"
    if [[ "$failures" != "0" ]]; then
        # Process substitution, not a pipe: a piped while-loop runs in a
        # subshell and its appends to FAILED would be discarded.
        while IFS= read -r entry; do
            FAILED+=("model: ${entry#fail.}")
        done < <(find "$status" -name 'fail.*' -exec basename {} \;)
    fi

    # The HF CLI keeps its own copy under the staging dir; 77-83 GB is not
    # something to store twice on a 150 GB volume.
    rm -rf "$STAGING/hf"
}

phase4_workflows() {
    local name dest_dir out stage

    log ""
    log "──── phase 4: workflows ────"

    dest_dir="$COMFY_ROOT/user/default/workflows"
    mkdir -p "$dest_dir"

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        out="$dest_dir/$name"
        stage="$STAGING/${name}.part"

        if [[ -s "$out" ]]; then
            log " [SKIP] $name already present"
            continue
        fi

        rm -f "$stage"

        if fetch_mirror_file "$name" "$stage" && [[ -s "$stage" ]]; then
            mv -f "$stage" "$out"
            log " ✓ $name"
        else
            rm -f "$stage"
            log " ❌ $name"
            FAILED+=("workflow: $name")
        fi
    done <<< "$(active_workflow_lines)"
}

phase5_restart_and_verify() {
    local pattern='[p]ython.*main\.py.*--port(=|[[:space:]])8188'
    local args_file="/workspace/runpod-slim/comfyui_args.txt"
    local log_start=1 new_log new_pid dir url sha missing=0 extra
    local -a args=(--listen 0.0.0.0 --port 8188 --enable-cors-header)

    log ""
    log "──── phase 5: restart and verify ────"

    if [[ "${NODES_CHANGED:-0}" != "1" ]] && pgrep -f "$pattern" >/dev/null 2>&1; then
        log "• no node changes and ComfyUI is running — no restart needed"
        return 0
    fi

    if [[ -f "$args_file" ]]; then
        extra="$(grep -vE '^[[:space:]]*(#|$)' "$args_file" | tr '\n' ' ' || true)"
        if [[ -n "$extra" ]]; then
            # Intentional word splitting: these are CLI flags.
            # shellcheck disable=SC2206
            local parsed=( $extra )
            args+=("${parsed[@]}")
        fi
    fi

    if pgrep -f "$pattern" >/dev/null 2>&1; then
        log "• stopping the running ComfyUI"
        pkill -f "$pattern" 2>/dev/null || true
        for _ in {1..40}; do
            pgrep -f "$pattern" >/dev/null 2>&1 || break
            sleep 0.5
        done
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            log "❌ the old ComfyUI process would not stop; not starting a second one"
            FAILED+=("phase 5: stale ComfyUI process")
            return 1
        fi
    fi

    log_start=$(( $(wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

    cd "$COMFY_ROOT" || return 1
    nohup "$PYTHON" main.py "${args[@]}" >> "$LOG" 2>&1 </dev/null &
    new_pid=$!
    log "• started ComfyUI as PID $new_pid"

    for _ in {1..180}; do
        if ! kill -0 "$new_pid" 2>/dev/null; then
            log "❌ ComfyUI exited during startup"
            FAILED+=("phase 5: ComfyUI exited")
            return 1
        fi
        new_log="$(tail -n +"$log_start" "$LOG" 2>/dev/null || true)"
        grep -Fq "Starting server" <<< "$new_log" && break
        sleep 1
    done

    new_log="$(tail -n +"$log_start" "$LOG" 2>/dev/null || true)"
    if ! grep -Fq "Starting server" <<< "$new_log"; then
        log "❌ ComfyUI did not finish starting within 180s"
        FAILED+=("phase 5: startup timeout")
        return 1
    fi

    log "• ComfyUI reached server startup; checking node packs"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue
        if grep -Fq "/custom_nodes/${dir}" <<< "$new_log"; then
            log "   ✓ loaded: $dir"
        else
            log "   ✗ NOT LOADED: $dir"
            missing=$(( missing + 1 ))
        fi
    done <<< "$(active_node_pack_lines)"

    if (( missing > 0 )); then
        FAILED+=("phase 5: $missing node pack(s) did not load")
    fi
}

summary() {
    log ""
    log "──────────────────────────────────"
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        log "✅ MiniMax H3 provisioning finished — ComfyUI is ready on port 8188."
        log "   Both workflows are in ComfyUI's saved-workflow list."
    else
        log "⚠️  finished with ${#FAILED[@]} problem(s):"
        printf '   ❌ %s\n' "${FAILED[@]}"
        log "Re-run this script; it retries only what is missing:"
        log "   bash /workspace/provision_minimax.sh"
    fi
    log "════ done: $(date) ════"
}

main() {
    # --build-sage runs via nohup ... >> "$LOG", so setup_logging's tee
    # would duplicate every line. Skip it for that mode.
    [[ "${1:-}" != "--build-sage" ]] && setup_logging

    # Keep HuggingFace's caches on the 150 GB volume, not the 25 GB container
    # disk: the Xet backend keeps a chunk cache of up to ~10 GB, and the
    # largest model is 27 GB. Exported here, inside main, so that sourcing
    # the script for tests still changes nothing.
    export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
    export HF_XET_CACHE="${HF_XET_CACHE:-$HF_HOME/xet}"

    log ""
    log "════ MiniMax H3 provisioning started (${1:-manual}): $(date) ════"

    # Say which template this pod is before doing anything, so a log read
    # after the fact shows at a glance whether ControlNet was meant to be here.
    if controlnet_enabled; then
        log "template: minimax-h3-controlnet (MINIMAX_CONTROLNET=${MINIMAX_CONTROLNET})"
    else
        log "template: minimax-h3 (MINIMAX_CONTROLNET=${MINIMAX_CONTROLNET:-unset}, base only)"
    fi

    if [[ "${1:-}" == "--build-sage" ]]; then
        build_sage_wheel
        exit 0
    fi

    phase0_wait_for_comfyui || { summary; exit 1; }
    phase1_sageattention
    phase2_node_packs
    phase3_models
    phase4_workflows
    phase5_restart_and_verify
    summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
