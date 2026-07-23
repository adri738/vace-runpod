# Own VACE RunPod Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the creator's rotted RunPod template with the user's own: a RunPod template wrapping the official `runpod/comfyui` image plus a user-owned provisioning script on GitHub that installs the VACE workflow's nodes and models automatically at boot.

**Architecture:** A public GitHub repo (`vace-runpod`) holds `provision_vace.sh` and a README. The RunPod template points at `runpod/comfyui:cuda12.8` and overrides the entrypoint with a wrapper that launches the image's normal `/start.sh` untouched while a background job waits for ComfyUI to be set up, downloads the script from GitHub, runs it, and restarts ComfyUI only if new node packs were installed.

**Tech Stack:** Bash, git, GitHub (web UI, no CLI installed), RunPod console. No Docker builds.

## Global Constraints

- Base image: `runpod/comfyui:cuda12.8` (official, built from runpod-workers/comfyui-base; ComfyUI pinned v0.26.2, torch 2.10.0+cu128, entrypoint `/start.sh`, ComfyUI at `/workspace/runpod-slim/ComfyUI`, venv `.venv-cu128`, ComfyUI-Manager and KJNodes pre-baked).
- The provisioning script must NEVER update ComfyUI and never install torch/torchvision/torchaudio; it must export `PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt` when that file exists.
- Script must be idempotent (safe on every boot) and must not hardcode the ComfyUI path (locate dynamically).
- All node packs pinned to the exact commit SHAs listed in Task 2 (verified live 2026-07-23).
- All model URLs are the original sources listed in Task 2 (each returned HTTP 200 on 2026-07-23).
- The workflow JSON (`VACE_IMAGE-TO-VIDEO_CONTROLNET.json`) is paid Patreon content — it must NOT be committed to the public repo. It stays on the user's PC and gets dragged into ComfyUI per session.
- The user is a beginner: every manual GitHub/RunPod step must be written as exact click-by-click instructions.
- Working directory for all tasks: `C:\Users\Trabajo\Documents\Projectos\Claude_Template_Aitrpeneur` (already a git repo, branch `main`).

---

### Task 1: Keep the creator's files out of the public repo

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: a repo where `git add .` can never accidentally publish the creator's paid workflow or debugging artifacts. Later tasks commit only `provision_vace.sh`, `README.md`, `.gitignore`, and `docs/`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Creator's paid/reference material — never publish
VACE_IMAGE-TO-VIDEO_CONTROLNET.json
VACE_AUTO_INSTALL-RUNPOD.sh
instructions_aitrepeneur_comfyui_videoVACE.txt

# Debugging artifacts from the old pod
comfyui_error.log
error_screenshot.png
```

- [ ] **Step 2: Verify git now ignores them**

Run (Git Bash, in the repo folder):
```bash
git status --short
```
Expected: only `?? .gitignore` (and `docs/` if uncommitted plan files exist). None of the five ignored files appear.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore creator's paid content and debug artifacts"
```

---

### Task 2: Write the provisioning script

**Files:**
- Create: `provision_vace.sh`

**Interfaces:**
- Consumes: nothing (self-contained).
- Produces: `provision_vace.sh` at repo root. Task 4 publishes it; Task 5's wrapper downloads it from `https://raw.githubusercontent.com/<GITHUB_USER>/vace-runpod/main/provision_vace.sh` and runs `bash provision_vace.sh --restart-comfyui`. Manual fallback runs it with no argument.
- Behavior contract: exit 0 unless ComfyUI root is missing; logs to `/workspace/provision.log`; restarts ComfyUI only when called with `--restart-comfyui` AND it cloned at least one new node pack.

- [ ] **Step 1: Write `provision_vace.sh` with exactly this content**

```bash
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
get_node rgthree-comfy               https://github.com/rgthree/rgthree-comfy.git               27b4f4cdcf3b127c29d5d8135ac1536ecbd4c383
get_node ComfyUI-VideoHelperSuite    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git 4ee72c065db22c9d96c2427954dc69e7b908444b
get_node ComfyUI-KJNodes             https://github.com/kijai/ComfyUI-KJNodes.git                e27a505b3ba6ce42687fe00500deda103d9d6071
get_node comfyui_controlnet_aux      https://github.com/Fannovel16/comfyui_controlnet_aux.git    e8b689a513c3e6b63edc44066560ca5919c0576e
get_node ComfyUI_LayerStyle          https://github.com/chflame163/ComfyUI_LayerStyle.git        02acdc50affb84cd24f341d1fc2d3a9134b2ad3d
get_node ComfyUI-Easy-Use            https://github.com/yolain/ComfyUI-Easy-Use.git              54d080bf6a4f52da287e984f305243c10db097f5
get_node Derfuu_ComfyUI_ModdedNodes  https://github.com/Derfuu/Derfuu_ComfyUI_ModdedNodes.git    d0905bed31249f2bd0814c67585cf4fe3c77c015
get_node ComfyUI-Frame-Interpolation https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git 26545cc2dd95bc3d27f056016300673bdeee78f5
get_node gguf                        https://github.com/calcuis/gguf.git                          080e4ee22410687bb644c8aa8da7d808fe267fce
get_node ComfyUI-GGUF                https://github.com/city96/ComfyUI-GGUF.git                   6ea2651e7df66d7585f6ffee804b20e92fb38b8a
get_node ComfyUI-Manager             https://github.com/ltdrdata/ComfyUI-Manager.git              7955e638db7d4a4b8bf7a614e724a2013b83dfd7

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
```

- [ ] **Step 2: Syntax-check it**

Run (Git Bash, repo folder):
```bash
bash -n provision_vace.sh && echo SYNTAX_OK
```
Expected: `SYNTAX_OK`

- [ ] **Step 3: Dry-check the failure path locally**

The only environment-independent branch we can test on Windows is the abort when no ComfyUI exists. Run:
```bash
bash -c 'export MSYS=noglob; bash ./provision_vace.sh; echo "exit=$?"'
```
Expected: output contains `❌ Could not find a ComfyUI folder under /workspace` and `exit=1` (on Windows Git Bash, `/workspace` doesn't exist — that's the point). If Git Bash maps `/workspace` oddly and it exits 0, skip this step; the real test happens on the pod in Task 6.

- [ ] **Step 4: Commit**

```bash
git add provision_vace.sh
git commit -m "feat: add pinned VACE provisioning script for RunPod official ComfyUI image"
```

---

### Task 3: Write the README (the user's own instructions)

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: script name `provision_vace.sh` and its `--restart-comfyui` flag from Task 2.
- Produces: the instructions Task 5 and Task 6 reference. Contains the literal template values so the user can rebuild the template from scratch if ever needed.

- [ ] **Step 1: Write `README.md` with exactly this content** (replace `<GITHUB_USER>` in BOTH places once the GitHub username is known in Task 4 — if writing this file before Task 4, put the placeholder and fix it in Task 4 Step 5):

````markdown
# VACE on RunPod — my own template

My replacement for the Aitrepreneur RunPod template, which broke in 2026
(its ComfyUI was frozen in 2024 and the mandatory "Update ComfyUI" step
no longer works). This setup uses RunPod's **official, maintained ComfyUI
image** and installs everything the VACE image-to-video workflow needs
automatically at boot. There is **no "update ComfyUI" step — never click
Update in the Manager.**

## Normal use

1. RunPod console → **Pods** → **Deploy**. Pick a GPU with **at least 24 GB
   VRAM** (RTX 4090 is the sweet spot). Select **my template** `vace-comfyui`.
2. Deploy On-Demand. First boot downloads ~23 GB of models — takes
   **10–15 minutes**. Watch progress: open the pod → **Logs** tab, wait for
   the line `✅ VACE provisioning finished`.
   (Alternative: Connect → port 8888 JupyterLab → Terminal →
   `tail -f /workspace/provision.log`.)
3. Connect → **HTTP Service, port 8188** (ComfyUI).
4. Drag `VACE_IMAGE-TO-VIDEO_CONTROLNET.json` from my PC into the browser
   window. The workflow JSON is **not** in this repo (paid content) — it
   lives in my local folder `Claude_Template_Aitrpeneur`.
5. In the **"GGUF VACE 14B"** node, open the dropdown and select
   `Wan2.1_14B_VACE-Q8_0.gguf` (the saved workflow points at a Q4 file
   that we don't use; Q8 is better quality). Then generate.

Stop/start: stopping the pod keeps `/workspace` (models, nodes). Restart
takes ~1–2 minutes and everything is still there.

## If something goes wrong

**Symptom: pod is up but `/workspace/provision.log` doesn't exist.**
The boot wrapper didn't run. Fallback (always works): Connect → port 8888
JupyterLab → Terminal, then:

```bash
cd /workspace
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/vace-runpod/main/provision_vace.sh -o provision_vace.sh
bash provision_vace.sh --restart-comfyui
```

**Symptom: workflow shows red "missing node" boxes.**
Provisioning probably hadn't finished (or a clone failed). Check the end
of `/workspace/provision.log` for ❌ lines, re-run the fallback command
above, then refresh the ComfyUI browser tab.

**Symptom: a model is missing from a dropdown.**
Same fallback command — it re-downloads only what's missing.

## Template settings (to rebuild the template from scratch)

| Setting | Value |
|---|---|
| Container Image | `runpod/comfyui:cuda12.8` |
| Container Disk | 20 GB |
| Volume Disk | 80 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8188,8888,8080` |
| Expose TCP Ports | `22` |

Container Start Command (one line, exactly):

```
{"entrypoint": ["bash", "-c", "nohup bash -c 'i=0; while [ ! -d /workspace/runpod-slim/ComfyUI/custom_nodes ] && [ $i -lt 120 ]; do sleep 5; i=$((i+1)); done; sleep 30; curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/vace-runpod/main/provision_vace.sh -o /workspace/provision_vace.sh; bash /workspace/provision_vace.sh --restart-comfyui' > /workspace/provision-boot.log 2>&1 & exec /start.sh"]}
```

What it does: starts the official image's `/start.sh` unchanged; in the
background, waits until the image has set up ComfyUI (max 10 min), then
downloads the latest `provision_vace.sh` from this repo and runs it.
ComfyUI is restarted automatically only when new node packs were installed
(i.e. on the first boot).

## What gets installed

Node packs (pinned commits — see `provision_vace.sh`): rgthree-comfy,
VideoHelperSuite, KJNodes, controlnet_aux, LayerStyle, Easy-Use, Derfuu,
Frame-Interpolation, calcuis/gguf, city96/ComfyUI-GGUF, Manager.

Models (original sources, ~23 GB): WAN 2.1 VACE 14B Q8 GGUF (QuantStack),
CausVid LoRA (Kijai), UMT5-XXL fp8 text encoder + WAN 2.1 VAE (Comfy-Org),
4x-ClearRealityV1 + RealESRGAN_x4plus_anime_6B upscalers.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: usage instructions and template settings"
```

---

### Task 4: Publish the repo to GitHub

**Files:**
- Modify: `README.md` (replace `<GITHUB_USER>` placeholders)

**Interfaces:**
- Consumes: local git repo with Tasks 1–3 committed.
- Produces: public repo `https://github.com/<GITHUB_USER>/vace-runpod` and the working raw URL `https://raw.githubusercontent.com/<GITHUB_USER>/vace-runpod/main/provision_vace.sh` that Task 5's start command uses.

- [ ] **Step 1: Ask the user for their GitHub username** (and to log in at github.com; if they have no account, they create one at https://github.com/signup — a free account, and per safety policy account creation is done by the user themselves, never by Claude).

- [ ] **Step 2: User creates the empty repo (browser, ~1 min)**

Tell the user, click by click:
1. Go to https://github.com/new
2. **Repository name:** `vace-runpod`
3. **Public** selected (required: RunPod must fetch the script without a login)
4. Leave ALL checkboxes off (no README, no .gitignore, no license — we push our own)
5. Click **Create repository**

- [ ] **Step 3: Replace the placeholders in README.md**

Edit `README.md`: replace both occurrences of `<GITHUB_USER>` with the real username. Commit:
```bash
git add README.md
git commit -m "docs: fill in GitHub username"
```

- [ ] **Step 4: Push**

Run (Git Bash, repo folder — replace `<GITHUB_USER>`):
```bash
git remote add origin https://github.com/<GITHUB_USER>/vace-runpod.git
git push -u origin main
```
Expected: a browser window may pop up asking the user to sign in to GitHub (Git Credential Manager) — the user completes it themselves. Push ends with `main -> main`.

- [ ] **Step 5: Verify the raw URL works (the critical artifact)**

```bash
curl -fsSL "https://raw.githubusercontent.com/<GITHUB_USER>/vace-runpod/main/provision_vace.sh" | head -5
```
Expected: the first 5 lines of the script (`#!/usr/bin/env bash` …). If 404: wait one minute (raw cache) and retry; then check repo is Public.

---

### Task 5: Create the RunPod template (user's account, browser)

**Files:** none (RunPod console only)

**Interfaces:**
- Consumes: the verified raw URL from Task 4.
- Produces: a template named `vace-comfyui` in the user's RunPod account, used by Task 6.

- [ ] **Step 1: Walk the user through the console, click by click**

1. Log in at https://console.runpod.io
2. Left sidebar → **Templates** (under Manage) → **New Template**
3. Fill in:
   - **Name:** `vace-comfyui`
   - **Template Type:** Pod
   - **Compute:** Nvidia GPU
   - **Container Image:** `runpod/comfyui:cuda12.8`
   - **Container Start Command:** paste the one-line JSON from the README's "Template settings" section (it already contains the real username after Task 4 Step 3) — exactly as written, single line
   - **Container Disk:** 20 GB
   - **Volume Disk:** 80 GB
   - **Volume Mount Path:** `/workspace`
   - **Expose HTTP Ports:** `8188,8888,8080`
   - **Expose TCP Ports:** `22`
   - Environment variables: optional — recommend adding `FILEBROWSER_PASSWORD` set to a password of the user's choosing (the image's default is `adminadmin12`, publicly known)
4. Click **Save Template**

- [ ] **Step 2: Verify**

The template `vace-comfyui` appears in the Templates list. Open it once more and confirm the start command survived saving as one line (no truncation — it ends with `exec /start.sh\"]}`).

---

### Task 6: Test deployment end-to-end

**Files:** none (RunPod console + pod)

**Interfaces:**
- Consumes: template `vace-comfyui` from Task 5.
- Produces: verified working template; permission to terminate the old creator-template pod.

- [ ] **Step 1: Deploy a test pod**

Console → **Pods** → **Deploy**. GPU: RTX 4090 (or anything ≥24 GB VRAM, CUDA 12.8+). Template: `vace-comfyui`. **On-Demand** → Deploy.

- [ ] **Step 2: Watch first-boot provisioning**

Open the pod → **Logs** tab. Within ~3–5 minutes the image finishes its own setup; then provisioning lines appear (`════ VACE provisioning started`). Total wait 10–15 min. Success = `✅ VACE provisioning finished — ComfyUI is ready.` followed by the restart line `ComfyUI restarted on port 8188.`
- If after 10 minutes there is **no** `provision` line at all: the wrapper didn't fire. Use the README's fallback (Jupyter terminal → curl + bash command). If the fallback works, the template's start command needs re-checking (Task 5 Step 2); fix and redeploy.
- If ❌ lines appear: note which item failed, re-run the fallback command; only that item is retried.

- [ ] **Step 3: Verify the workflow loads clean**

Connect → HTTP 8188. Drag the local `VACE_IMAGE-TO-VIDEO_CONTROLNET.json` into the window. Expected: **no "Missing Node Types" dialog**. In the "GGUF VACE 14B" node dropdown select `Wan2.1_14B_VACE-Q8_0.gguf`.

- [ ] **Step 4: Run one short generation**

Load an input image, set a small frame count (e.g. 33 frames / 480p) and click Queue. Expected: a video appears in the output node with no red error node. (First run also auto-downloads small DWPose/DepthAnything/RIFE weights — a one-time extra minute.)

- [ ] **Step 5: Verify stop/start persistence**

Stop the pod (not terminate). Start it again. Expected: boot in ~1–2 min; provision.log shows all "already present — skip" lines and NO restart line; workflow still loads with no missing nodes.

- [ ] **Step 6: Clean up**

- Ask the user to confirm, then have the user **terminate the old pod** made from the creator's template (it is stopped and still billing storage; nothing on it is needed).
- Commit any final tweaks made during testing:
```bash
git add -A
git commit -m "fix: adjustments from first live test"
git push
```

---

## Self-review notes

- Spec coverage: architecture (Tasks 4–5), script requirements incl. pinned nodes + original-source models + PIP_CONSTRAINT + dynamic root (Task 2), README with fallback path (Task 3), never-update rule (script + README), verification checklist (Task 6), out-of-scope items untouched. Paid-content concern resolved via Task 1 (.gitignore) — spec listed the workflow JSON as a repo file; this plan intentionally deviates (keeps it local) because the JSON is paid Patreon content and the repo is public. The workflow is only ever needed browser-side, so nothing breaks.
- The entrypoint-JSON form (`{"entrypoint": [...]}`) is used because the image defines `ENTRYPOINT ["/start.sh"]`, and a plain start command would be passed as arguments to it and silently ignored. Fallback documented in README in case RunPod changes semantics.
- Type/name consistency checked: script name, flag `--restart-comfyui`, template name `vace-comfyui`, repo name `vace-runpod`, gguf filename `Wan2.1_14B_VACE-Q8_0.gguf` are identical across Tasks 2–6.
