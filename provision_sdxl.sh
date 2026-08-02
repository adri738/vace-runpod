#!/usr/bin/env bash
# provision_sdxl.sh — sets up SDXL (Illustrious) models on the
# dcainet/forge-min image (Stable Diffusion WebUI Forge for RunPod).
#
# Idempotent: safe on every boot; skips whatever already exists.
#
# Usage:
#   bash provision_sdxl.sh          # manual run (Jupyter terminal)
#   bash provision_sdxl.sh --boot   # boot mode: waits for the image's
#                                   # first-boot Forge build before starting
set -uo pipefail

MODE="${1:-}"
LOG="/workspace/provision_sdxl.log"
mkdir -p /workspace
exec > >(tee -a "$LOG") 2>&1
echo ""
echo "════ SDXL Forge provisioning started (mode: ${MODE:-manual}): $(date) ════"

FAILED=()

# ── 0. CLIP fix ─────────────────────────────────────────────────────
# Forge's own launcher builds openai/CLIP from source, whose ancient
# setup.py needs pkg_resources — removed from setuptools in 2026. That
# crash-loops the whole container. Installing CLIP ourselves (with an
# old setuptools and no build isolation) makes Forge skip that step.
VENVPY="/workspace/forge/venv/bin/python"
fix_clip() {
    if [[ ! -x "$VENVPY" ]]; then
        echo "• venv not built yet — CLIP fix will run on the next boot"
        return 0
    fi
    if "$VENVPY" -c "import clip" 2>/dev/null; then
        echo "• CLIP already installed — skip"
        return 0
    fi
    echo "• installing CLIP with pkg_resources workaround..."
    "$VENVPY" -m pip install -q "setuptools==69.5.1" wheel || { FAILED+=("clip fix: setuptools pin"); return 0; }
    if "$VENVPY" -m pip install -q --no-build-isolation \
        "https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip"; then
        echo "• CLIP installed ✔"
    else
        FAILED+=("clip fix: CLIP build")
    fi
}

# --pre mode: runs synchronously BEFORE the image's entrypoint each boot
if [[ "$MODE" == "--pre" ]]; then
    fix_clip
    echo "════ pre-start done: $(date) ════"
    exit 0
fi

find_dirs() {
    # forge-min layout first, classic layouts as fallback
    FORGE=""
    MODELS=""
    for d in /workspace/forge/stable-diffusion-webui-forge /workspace/stable-diffusion-webui-forge; do
        [[ -d "$d" ]] && { FORGE="$d"; break; }
    done
    if [[ -d /workspace/forge/models ]]; then
        MODELS="/workspace/forge/models"
    elif [[ -n "$FORGE" && -d "$FORGE/models" ]]; then
        MODELS="$FORGE/models"
    fi
}

# ── 1. In boot mode, wait for the image's first-boot Forge build ───
find_dirs
if [[ "$MODE" == "--boot" ]]; then
    WAITED=0
    until [[ -n "$MODELS" ]] || [[ $WAITED -ge 1500 ]]; do
        sleep 10
        WAITED=$((WAITED+10))
        find_dirs
    done
fi
if [[ -z "$MODELS" ]]; then
    echo "❌ Forge models folder not found under /workspace — aborting."
    echo "   (Is this pod using the dcainet/forge-min image? Did the first-boot build finish?)"
    exit 1
fi
echo "Forge root: ${FORGE:-not found yet}"
echo "Models dir: $MODELS"

# In boot/manual mode too: make sure CLIP is fixed once the venv exists
fix_clip

# Embeddings folder: forge-min keeps it under models/, classic keeps it in the webui root
if [[ -d "$MODELS/embeddings" ]]; then
    EMBED="$MODELS/embeddings"
elif [[ -n "$FORGE" ]]; then
    EMBED="$FORGE/embeddings"
else
    EMBED="$MODELS/embeddings"
fi

# ── 2. Models — resumable downloads, skip when present ─────────────
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
# Checkpoint (6.9 GB)
grab "$MODELS/Stable-diffusion/waiNSFWIllustrious_v120.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/waiNSFWIllustrious_v120.safetensors?download=true"
# LoRA (362 MB)
grab "$MODELS/Lora/extreme-sex-v1.0-illustriousxl.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/extreme-sex-v1.0-illustriousxl.safetensors?download=true"
# Embedding (295 KB) — NOT a LoRA; used by typing "lazypos" in the prompt
grab "$EMBED/lazypos.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/lazypos.safetensors?download=true"
# ControlNet Union SDXL (2.5 GB) — renamed from its meaningless original name
grab "$MODELS/ControlNet/controlnet-union-sdxl-1.0.safetensors" \
     "https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model.safetensors?download=true"

# (Forge updates: use the image's native AUTO_UPDATE_FORGE=true env var if
#  ever needed — deliberately off by default, same pin philosophy as VACE.)

# ── 3. Quicksettings: add Clip Skip control to the top bar ─────────
echo "──── config ────"
if [[ -z "$FORGE" ]]; then
    # Forge dir may appear after models dir on first boot — wait a bit more
    WAITED=0
    until [[ -n "$FORGE" ]] || [[ $WAITED -ge 600 ]]; do
        sleep 10
        WAITED=$((WAITED+10))
        find_dirs
    done
fi
if [[ -z "$FORGE" ]]; then
    FAILED+=("config patch (Forge dir never appeared)")
    CHANGED="skipped"
else
CHANGED=$(python3 - "$FORGE/config.json" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
cfg = {}
if os.path.exists(p):
    try:
        with open(p) as f:
            cfg = json.load(f)
    except Exception:
        print("error"); sys.exit(0)
qs = cfg.get("quicksettings_list", ["sd_model_checkpoint"])
if "CLIP_stop_at_last_layers" in qs:
    print("unchanged"); sys.exit(0)
qs.append("CLIP_stop_at_last_layers")
cfg["quicksettings_list"] = qs
with open(p, "w") as f:
    json.dump(cfg, f, indent=4)
print("changed")
PYEOF
)
fi
if [[ "$CHANGED" == "error" ]]; then
    FAILED+=("config patch (config.json unreadable)")
fi
echo "quicksettings CLIP_stop_at_last_layers: $CHANGED"

# ── 4. If the setting changed while Forge was already running ──────
if [[ "$CHANGED" == "changed" ]] && pgrep -f "launch.py|webui.sh" >/dev/null 2>&1; then
    echo "ℹ️  Forge was already running: to see the Clip Skip box in the top bar,"
    echo "   click 'Reload UI' at the bottom of Forge's Settings tab"
    echo "   (or Stop → Start the pod once)."
fi

# ── 5. Summary ──────────────────────────────────────────────────────
echo "──────────────────────────────────"
if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "✅ SDXL provisioning finished — Forge is ready on port 7860."
else
    echo "⚠️  Finished with ${#FAILED[@]} problem(s):"
    printf '   ❌ %s\n' "${FAILED[@]}"
    echo "Re-run this script to retry only the missing pieces."
fi
echo "════ done: $(date) ════"
