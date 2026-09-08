#!/usr/bin/env bash
# mirror_minimax.sh — populate the private MiniMax H3 model mirror.
#
# RUN THIS ONCE, EVER, from a RunPod pod (a cheap CPU-only pod is fine).
# It copies the 10 model files from the public source repo into the user's
# own private HuggingFace repo, verifying sha256 on the way, and uploads
# the two workflow JSONs if they are present locally.
#
# The write token is used here and only here. It must never be stored in
# the RunPod template.
#
# Usage:
#   export HF_WRITE_TOKEN=hf_xxx
#   bash mirror_minimax.sh
#
# Re-running is safe: files already in the mirror at the right size are
# skipped, so an interrupted run resumes where it stopped.

set -uo pipefail

SOURCE_REPO="${MINIMAX_SOURCE_REPO:-Aitrepreneur/FLX}"
MIRROR_REPO="${MINIMAX_HF_REPO:-adri738/minimax-h3-ultra-v3}"
WORK="${MINIMAX_MIRROR_WORK:-/workspace/.minimax_mirror}"

FAILED=()

log() { printf '%s\n' "$*"; }

# filename|expected bytes|sha256
MIRROR_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|27141342152|bc2ced0fbea64757fa9acddccfc0b3f4819d1dcf1da6c124d690d368be283923
minimax_h3_fl2va_pruned_int8_convrot.safetensors|20970379616|e889202c41dafb67b10d67b97f0d8541508036a6090af23425a5c2615d03c47a
minimax_h3_ref2va_pruned_int8_convrot.safetensors|20970379616|9255f52b6677845ad238f20dfaafa94727053694127ab7f255c048f0f9365779
minimax_h3_t1_image_vae_step1597.safetensors|5207808784|6c3d0bfa055986a803a566a862fcde283a1e63db62829e5ef4a2a5aebf50bb86
minimax_h3_video_vae_fp16.safetensors|5207808496|7c1f131492e7eddacaac9069a61b81bdd39de5cc96561e677c5eab1cdce5e522
sam3.1_multiplex_fp16.safetensors|1745546848|9ba99c92703c2e8b4f47de2d34a539bb8e18923049e238b780d70dbe6368eb03
minimax_h3_latent_upscaler_3d_fp16.safetensors|690592672|043e5a48e161610ef6c3ea974645220354d06fa618abca15f76d084812eb55c2
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|620285592|7098acf3ee75028fd9fcd948f50fcc8d995057fabb76f86bd3ca2c0ffc58e409
minimax_h3_audio_vae_fp32.safetensors|605254808|8e505d95dd1561d47abd43d4238fd40d9bb1ae9e147ed0a4cba778d76ae4db48
taeh3.safetensors|9791388|f0f60fa072089997f817402098c2fd90777cb2660dd79cf5df42fc1e3e08e527
'

mirror_manifest_lines() {
    printf '%s\n' "$MIRROR_MANIFEST" | grep -vE '^[[:space:]]*(#|$)'
}

require_tools() {
    local missing=0 t
    for t in hf curl; do
        command -v "$t" >/dev/null 2>&1 || { log "missing required tool: $t"; missing=1; }
    done
    if ! command -v sha256sum >/dev/null 2>&1; then
        log "missing required tool: sha256sum"
        missing=1
    fi
    [[ "$missing" -eq 0 ]]
}

# Size of a file already in the mirror, or empty if absent.
mirror_size() {
    local name="$1"
    curl -sIL --max-time 60 \
        -H "Authorization: Bearer ${HF_WRITE_TOKEN}" \
        "https://huggingface.co/${MIRROR_REPO}/resolve/main/${name}" \
        | tr -d '\r' \
        | grep -i '^x-linked-size:' \
        | tail -1 \
        | awk '{print $2}'
}

copy_one() {
    local name="$1" bytes="$2" want_sha="$3"
    local local_file="$WORK/$name"
    local present got_sha got_size

    present="$(mirror_size "$name")"
    if [[ "$present" == "$bytes" ]]; then
        log " [SKIP] $name already mirrored"
        return 0
    fi

    log " • downloading $name ($bytes bytes)"
    rm -rf "$WORK"
    mkdir -p "$WORK"

    # Every failure path below deletes the local copy before returning. The
    # sweep at the top of the next copy_one would eventually do it, but only
    # if there is a next one: a run killed here (pod evicted, OOM, network
    # drop) would otherwise strand up to 27 GB on the volume until the user
    # runs the script again. On a 60 GB recon pod that is half the disk.
    if ! hf download "$SOURCE_REPO" "$name" --local-dir "$WORK" >/dev/null; then
        rm -f "$local_file"
        FAILED+=("download: $name")
        return 1
    fi

    got_size="$(stat -c%s "$local_file" 2>/dev/null)"
    if [[ "$got_size" != "$bytes" ]]; then
        log "   ✗ size mismatch: expected $bytes, got ${got_size:-none}"
        rm -f "$local_file"
        FAILED+=("size: $name")
        return 1
    fi

    log "   verifying sha256 (this is the only time we pay for it)"
    got_sha="$(sha256sum "$local_file" | awk '{print $1}')"
    if [[ "$got_sha" != "$want_sha" ]]; then
        log "   ✗ sha256 mismatch"
        log "     expected $want_sha"
        log "     got      $got_sha"
        rm -f "$local_file"
        FAILED+=("sha256: $name")
        return 1
    fi

    log "   uploading to $MIRROR_REPO"
    if ! HF_TOKEN="$HF_WRITE_TOKEN" hf upload "$MIRROR_REPO" "$local_file" "$name" \
        --repo-type model >/dev/null; then
        rm -f "$local_file"
        FAILED+=("upload: $name")
        return 1
    fi

    rm -f "$local_file"
    log "   ✓ $name mirrored"
}

upload_workflows() {
    local f
    log "──── workflow JSONs ────"
    for f in MINIMAX_H3_ULTRA_WORKFLOW-V3.json MINIMAX_H3_ULTRA_TURBO_WORKFLOW-V3.json; do
        if [[ ! -f "$f" ]]; then
            log " [SKIP] $f not present in $(pwd) — upload it later from your PC"
            continue
        fi
        if HF_TOKEN="$HF_WRITE_TOKEN" hf upload "$MIRROR_REPO" "$f" "$f" \
            --repo-type model >/dev/null; then
            log " ✓ $f uploaded"
        else
            FAILED+=("upload: $f")
        fi
    done
}

main() {
    local name bytes sha

    if [[ -z "${HF_WRITE_TOKEN:-}" ]]; then
        log "HF_WRITE_TOKEN is not set."
        log "Create a write token at https://huggingface.co/settings/tokens, then:"
        log "  export HF_WRITE_TOKEN=hf_xxx"
        exit 1
    fi

    require_tools || exit 1

    log "════ mirroring $SOURCE_REPO -> $MIRROR_REPO ════"

    if ! HF_TOKEN="$HF_WRITE_TOKEN" hf repo create "$MIRROR_REPO" \
        --repo-type model --private 2>/dev/null; then
        log "(repo already exists, or creation was refused — continuing)"
    fi

    mkdir -p "$WORK"

    while IFS='|' read -r name bytes sha; do
        [[ -n "$name" ]] || continue
        copy_one "$name" "$bytes" "$sha"
    done <<< "$(mirror_manifest_lines)"

    upload_workflows

    rm -rf "$WORK"

    log "──────────────────────────────────"
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        log "✅ mirror complete — $MIRROR_REPO now holds everything the template needs."
    else
        log "⚠️  finished with ${#FAILED[@]} problem(s):"
        printf '   ❌ %s\n' "${FAILED[@]}"
        log "Re-run this script; it resumes and retries only what is missing."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
