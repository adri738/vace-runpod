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
