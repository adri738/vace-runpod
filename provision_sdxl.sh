#!/usr/bin/env bash
# provision_sdxl.sh — sets up SDXL (Illustrious) models on the
# ashleykza/forge image (Stable Diffusion WebUI Forge for RunPod).
#
# Idempotent: safe on every boot; skips whatever already exists.
#
# Usage:
#   bash provision_sdxl.sh          # manual run (Jupyter terminal)
#   bash provision_sdxl.sh --boot   # boot mode: waits for the image's
#                                   # first-boot sync before starting
#
# Optional: set UPDATE_FORGE=true (env var) to git-pull Forge upstream.
set -uo pipefail

MODE="${1:-}"
LOG="/workspace/provision_sdxl.log"
mkdir -p /workspace
exec > >(tee -a "$LOG") 2>&1
echo ""
echo "════ SDXL Forge provisioning started: $(date) ════"

FORGE="/workspace/stable-diffusion-webui-forge"

# ── 1. In boot mode, wait for the image to finish copying Forge ────
if [[ "$MODE" == "--boot" ]]; then
    WAITED=0
    until [[ -d "$FORGE/models" ]] || [[ $WAITED -ge 900 ]]; do
        sleep 10
        WAITED=$((WAITED+10))
    done
fi
if [[ ! -d "$FORGE/models" ]]; then
    echo "❌ Forge not found at $FORGE — aborting."
    echo "   (Is this pod using the ashleykza/forge image? Did first-boot sync finish?)"
    exit 1
fi
echo "Forge root: $FORGE"

FAILED=()

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
grab "$FORGE/models/Stable-diffusion/waiNSFWIllustrious_v120.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/waiNSFWIllustrious_v120.safetensors?download=true"
# LoRA (362 MB)
grab "$FORGE/models/Lora/extreme-sex-v1.0-illustriousxl.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/extreme-sex-v1.0-illustriousxl.safetensors?download=true"
# Embedding (295 KB) — NOT a LoRA; used by typing "lazypos" in the prompt
grab "$FORGE/embeddings/lazypos.safetensors" \
     "https://huggingface.co/marix64/NSFWIllustriousModel/resolve/main/lazypos.safetensors?download=true"
# ControlNet Union SDXL (2.5 GB) — renamed from its meaningless original name
grab "$FORGE/models/ControlNet/controlnet-union-sdxl-1.0.safetensors" \
     "https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model.safetensors?download=true"

# ── 3. Optional Forge update (off by default; pin philosophy) ──────
if [[ "${UPDATE_FORGE:-}" == "true" ]]; then
    echo "──── updating Forge (UPDATE_FORGE=true) ────"
    git -C "$FORGE" pull https://github.com/lllyasviel/stable-diffusion-webui-forge.git || FAILED+=("forge update")
fi

# ── 4. Quicksettings: add Clip Skip control to the top bar ─────────
echo "──── config ────"
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
if [[ "$CHANGED" == "error" ]]; then
    FAILED+=("config patch (config.json unreadable)")
fi
echo "quicksettings CLIP_stop_at_last_layers: $CHANGED"

# ── 5. Restart the WebUI if the config changed while it was running ─
if [[ "$CHANGED" == "changed" ]] && pgrep -f "webui.sh|launch.py" >/dev/null 2>&1; then
    echo "Restarting Forge so the new setting loads..."
    pkill -f "launch.py" 2>/dev/null || true
    pkill -f "webui.sh" 2>/dev/null || true
    sleep 3
    if [[ -x /start_forge.sh ]]; then
        /start_forge.sh
        echo "Forge restarting — WebUI ready on port 3001 in ~1 minute."
    else
        echo "⚠️  /start_forge.sh not found — stop/start the pod to load the setting."
    fi
fi

# ── 6. Summary ──────────────────────────────────────────────────────
echo "──────────────────────────────────"
if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "✅ SDXL provisioning finished — Forge is ready on port 3001."
else
    echo "⚠️  Finished with ${#FAILED[@]} problem(s):"
    printf '   ❌ %s\n' "${FAILED[@]}"
    echo "Re-run this script to retry only the missing pieces."
fi
echo "════ done: $(date) ════"
