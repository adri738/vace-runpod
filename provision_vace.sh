#!/usr/bin/env bash
# provision_vace.sh — installs everything the WAN 2.1 VACE workflow needs
# on top of RunPod's official ComfyUI image (runpod/comfyui:cuda12.8).
#
# Idempotent: safe to run on every boot; skips whatever already exists.
# Never updates ComfyUI. Never touches torch.
#
# Usage:
#   bash provision_vace.sh                    # manual run (Jupyter terminal)
#   bash provision_vace.sh --restart-comfyui  # boot mode: restart ComfyUI
#                                             # if new node packs were added
set -uo pipefail

MODE="${1:-}"
LOG="/workspace/provision.log"
mkdir -p /workspace
exec > >(tee -a "$LOG") 2>&1
echo ""
echo "════ VACE provisioning started: $(date) ════"

# ── 1. Locate ComfyUI (no hardcoded path) ──────────────────────────
COMFY_ROOT=""
for d in /workspace/runpod-slim/ComfyUI /workspace/ComfyUI /workspace/madapps/ComfyUI; do
    if [[ -d "$d/models" && -d "$d/custom_nodes" ]]; then COMFY_ROOT="$d"; break; fi
done
if [[ -z "$COMFY_ROOT" ]]; then
    CAND=$(find /workspace -maxdepth 3 -type d -name custom_nodes 2>/dev/null | head -1)
    [[ -n "$CAND" ]] && COMFY_ROOT=$(dirname "$CAND")
fi
if [[ -z "$COMFY_ROOT" ]]; then
    echo "❌ Could not find a ComfyUI folder under /workspace — aborting."
    echo "   (Has the base image finished its first-time setup? Check /start.sh logs.)"
    exit 1
fi
echo "ComfyUI root: $COMFY_ROOT"
cd "$COMFY_ROOT"

# ── 2. Use the same Python that ComfyUI runs with ──────────────────
PY="python3"
for v in "$COMFY_ROOT"/.venv*/bin/python "$COMFY_ROOT"/venv/bin/python; do
    if [[ -x "$v" ]]; then PY="$v"; break; fi
done
echo "Python: $PY"

# Respect the image's package pins (protects torch from being replaced)
if [[ -f /opt/comfyui-runtime-constraints.txt ]]; then
    export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
fi

FAILED=()
CLONED=0

# ── 3. Custom nodes, each pinned to a known-good commit ────────────
get_node() {   # get_node <folder> <git url> <commit sha>
    local dir="$1" url="$2" sha="$3"
    if [[ -d "custom_nodes/$dir" ]]; then
        echo "• $dir already present — skip"
        return
    fi
    echo "• installing $dir @ ${sha:0:12}"
    if git clone --recursive --quiet "$url" "custom_nodes/$dir" \
       && git -C "custom_nodes/$dir" checkout --quiet "$sha"; then
        CLONED=$((CLONED+1))
        if [[ -f "custom_nodes/$dir/requirements.txt" ]]; then
            "$PY" -m pip install -q -r "custom_nodes/$dir/requirements.txt" || FAILED+=("deps: $dir")
        fi
    else
        FAILED+=("node: $dir")
        rm -rf "custom_nodes/$dir"
    fi
}

echo "──── custom nodes ────"
get_node rgthree-comfy               https://github.com/rgthree/rgthree-comfy.git                27b4f4cdcf3b127c29d5d8135ac1536ecbd4c383
get_node ComfyUI-VideoHelperSuite    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git 4ee72c065db22c9d96c2427954dc69e7b908444b
get_node ComfyUI-KJNodes             https://github.com/kijai/ComfyUI-KJNodes.git                e27a505b3ba6ce42687fe00500deda103d9d6071
get_node comfyui_controlnet_aux      https://github.com/Fannovel16/comfyui_controlnet_aux.git    e8b689a513c3e6b63edc44066560ca5919c0576e
get_node ComfyUI_LayerStyle          https://github.com/chflame163/ComfyUI_LayerStyle.git        02acdc50affb84cd24f341d1fc2d3a9134b2ad3d
get_node ComfyUI-Easy-Use            https://github.com/yolain/ComfyUI-Easy-Use.git              54d080bf6a4f52da287e984f305243c10db097f5
get_node Derfuu_ComfyUI_ModdedNodes  https://github.com/Derfuu/Derfuu_ComfyUI_ModdedNodes.git    d0905bed31249f2bd0814c67585cf4fe3c77c015
get_node ComfyUI-Frame-Interpolation https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git 26545cc2dd95bc3d27f056016300673bdeee78f5
get_node gguf                        https://github.com/calcuis/gguf.git                         080e4ee22410687bb644c8aa8da7d808fe267fce
get_node ComfyUI-GGUF                https://github.com/city96/ComfyUI-GGUF.git                  6ea2651e7df66d7585f6ffee804b20e92fb38b8a
get_node ComfyUI-Manager             https://github.com/ltdrdata/ComfyUI-Manager.git             7955e638db7d4a4b8bf7a614e724a2013b83dfd7

# Frame-Interpolation ships install.py instead of requirements.txt
if [[ -d "custom_nodes/ComfyUI-Frame-Interpolation" && ! -f "custom_nodes/ComfyUI-Frame-Interpolation/.deps_done" ]]; then
    echo "• Frame-Interpolation dependencies (install.py)"
    if (cd custom_nodes/ComfyUI-Frame-Interpolation && "$PY" install.py); then
        touch custom_nodes/ComfyUI-Frame-Interpolation/.deps_done
    else
        FAILED+=("deps: ComfyUI-Frame-Interpolation")
    fi
fi

# Small extras some packs forget to declare
"$PY" -m pip install -q gguf piexif matplotlib opencv-python-headless || FAILED+=("deps: extras")

# ── 4. Models — original sources, resumable, skip when present ─────
grab() {   # grab <target path> <url>
    local t="$1" u="$2"
    if [[ -f "$t" ]]; then echo "• $(basename "$t") exists — skip"; return; fi
    echo "• downloading $(basename "$t")"
    mkdir -p "$(dirname "$t")"
    if curl -L --fail --retry 3 -C - -o "$t.part" "$u"; then
        mv "$t.part" "$t"
    else
        FAILED+=("model: $(basename "$t")")
    fi
}

echo "──── models ────"
grab "models/unet/Wan2.1_14B_VACE-Q8_0.gguf" \
     "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q8_0.gguf?download=true"
grab "models/loras/Wan21_CausVid_14B_T2V_lora_rank32.safetensors" \
     "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32.safetensors?download=true"
grab "models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
     "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors?download=true"
grab "models/vae/wan_2.1_vae.safetensors" \
     "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors?download=true"
grab "models/upscale_models/4x-ClearRealityV1.pth" \
     "https://huggingface.co/skbhadra/ClearRealityV1/resolve/main/4x-ClearRealityV1.pth?download=true"
grab "models/upscale_models/RealESRGAN_x4plus_anime_6B.pth" \
     "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"

# ── 5. Restart ComfyUI at boot when new node packs were added ──────
if [[ "$MODE" == "--restart-comfyui" && $CLONED -gt 0 ]]; then
    echo "Restarting ComfyUI so $CLONED new node pack(s) load..."
    pkill -f "main.py --listen" 2>/dev/null || true
    sleep 3
    ARGS="--listen 0.0.0.0 --port 8188 --enable-cors-header"
    ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
    if [[ -s "$ARGS_FILE" ]]; then
        ARGS="$ARGS $(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')"
    fi
    cd "$COMFY_ROOT"
    nohup "$PY" main.py $ARGS >> /workspace/comfyui_restart.log 2>&1 &
    echo "ComfyUI restarted on port 8188."
fi

# ── 6. Summary ──────────────────────────────────────────────────────
echo "──────────────────────────────────"
if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "✅ VACE provisioning finished — ComfyUI is ready."
else
    echo "⚠️  Finished with ${#FAILED[@]} problem(s):"
    printf '   ❌ %s\n' "${FAILED[@]}"
    echo "Re-run this script to retry only the missing pieces."
fi
echo "════ done: $(date) ════"
