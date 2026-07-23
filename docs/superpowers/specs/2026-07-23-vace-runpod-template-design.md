# VACE RunPod Template — Design

**Date:** 2026-07-23
**Status:** Approved by user (pending written-spec review)

## Problem

The user runs Aitrepreneur's May-2025 VACE (WAN 2.1 image-to-video ControlNet) setup on RunPod
using the creator's template `lu30abf2pn`. That template is frozen at ComfyUI revision 2469
(2024-08-05, detached HEAD), PyTorch 2.4.0, ComfyUI-Manager 2.48.5. The workflow's core nodes
(`WanVaceToVideo`, `TrimVideoLatent`) require a ComfyUI from ~May 2025 or newer, so the creator's
instructions mandate clicking "Update ComfyUI" in the Manager. In July 2026 that update pulls
current packages (transformers 5.x, numpy 2.x, new frontend) into the 2024 venv, produces
dependency conflicts, and the backend dies mid-update — the UI shows
`Failed to update ComfyUI / TypeError: Failed to fetch`. The template has rotted; the mandatory
update step no longer works.

Additionally, all models download from the creator's personal HuggingFace repo
(`Aitrepreneur/FLX`) — a single point of failure the user wants out of.

## Goal

The user's **own RunPod template**: deploy a pod, wait for first boot, load
`VACE_IMAGE-TO-VIDEO_CONTROLNET.json`, generate. No manual terminal steps, no
"Update ComfyUI" step, no dependence on the creator's template or HF account.

## Decisions made with the user

- **Usage pattern:** occasional sessions — deploy when needed, terminate after. Models download
  on first boot; a network volume can be added later but is not part of v1.
- **No Docker image of our own.** The template wraps RunPod's official, actively maintained
  ComfyUI image (built from `runpod-workers/comfyui-base`).
- **Scope:** exactly the creator's VACE workflow. Success = the existing workflow JSON loads with
  no missing nodes and runs on a fresh pod.

## Architecture

Three user-owned pieces:

1. **Public GitHub repo** (working name `vace-runpod`) containing:
   - `provision_vace.sh` — the provisioning script (successor to `VACE_AUTO_INSTALL-RUNPOD.sh`)
   - `VACE_IMAGE-TO-VIDEO_CONTROLNET.json` — the workflow
   - `README.md` — the user's own usage instructions (replaces the creator's txt)
2. **RunPod template in the user's account:**
   - Image: RunPod's official ComfyUI image (exact image ref confirmed during implementation
     from the `comfyui-base` repo / official template)
   - Start command: wrapper that `curl`s `provision_vace.sh` fresh from the user's repo (raw
     GitHub URL), runs it, then execs the image's original entrypoint
   - Ports: 8188 (ComfyUI), 8888 (JupyterLab), 8080 (file browser), 22 (SSH)
   - Disks: ~20 GB container, 80 GB volume (`/workspace` persists across stop/start)
3. **No custom Docker image.** Base image supplies current ComfyUI + PyTorch; the script
   supplies everything VACE-specific. Updating the setup = editing the script on GitHub.

## Provisioning script requirements

Idempotent — runs on every boot, skips what exists. First boot ~10–15 min (model downloads);
subsequent boots ~1–2 min.

1. **Locate ComfyUI root dynamically** (directory under `/workspace` containing `models/` and
   `custom_nodes/`), no hardcoded path — resilient to base-image restructuring.
2. **Custom nodes** — clone at **pinned commits** (pins chosen and verified during
   implementation), then install each pack's `requirements.txt` into the image's Python env:
   - rgthree-comfy (`Power Lora Loader`, `Any Switch`, `Display Any`, `Label`,
     `Fast Groups Bypasser/Muter`)
   - ComfyUI-VideoHelperSuite (`VHS_*`)
   - ComfyUI-KJNodes (`ImageResizeKJv2`)
   - comfyui_controlnet_aux (`DWPreprocessor`, `DepthAnythingV2Preprocessor`,
     `CannyEdgePreprocessor`)
   - ComfyUI_LayerStyle (`LayerUtility: ImageRemoveAlpha`)
   - ComfyUI-Easy-Use (`easy imageRemBg`)
   - Derfuu_ComfyUI_ModdedNodes (`DF_Integer`)
   - ComfyUI-Frame-Interpolation (`RIFE VFI`)
   - calcuis/gguf (`LoaderGGUF` — the loader the workflow actually uses), plus
     city96/ComfyUI-GGUF as backup
   - ComfyUI-Manager only if the base image lacks it (it ships preinstalled)
3. **Models** — download from **original sources** (exact URLs verified during implementation),
   with resume (`curl -C -` or `wget -c`), skip-if-exists:
   | File | Target dir | Source |
   |---|---|---|
   | `Wan2.1-VACE-14B-Q8_0.gguf` | `models/unet/` | QuantStack/Wan2.1_14B_VACE-GGUF (HF) |
   | `Wan21_CausVid_14B_T2V_lora_rank32.safetensors` | `models/loras/` | Kijai/WanVideo_comfy (HF) |
   | `umt5_xxl_fp8_e4m3fn_scaled.safetensors` | `models/text_encoders/` | Comfy-Org/Wan_2.1_ComfyUI_repackaged (HF) |
   | `wan_2.1_vae.safetensors` | `models/vae/` | Comfy-Org/Wan_2.1_ComfyUI_repackaged (HF) |
   | `4x-ClearRealityV1.pth` | `models/upscale_models/` | original author release |
   | `RealESRGAN_x4plus_anime_6B.pth` | `models/upscale_models/` | xinntao/Real-ESRGAN releases |

   (DWPose, DepthAnything, RemBg, and RIFE weights auto-download on first use by their packs.)
4. **Never update ComfyUI** and never touch torch/xformers — the base image owns those.
5. **Logging:** everything to `/workspace/provision.log`; end with a per-item ✅/❌ summary.
   Continue past a failed model download (report at the end); abort only if ComfyUI root cannot
   be found.

## Error handling

- Script failures must not brick the pod: the wrapper runs the provisioner but starts the base
  image's services regardless, so Jupyter (8888) is always reachable for manual recovery.
- Fallback path documented in README: deploy the official RunPod ComfyUI template directly and
  run `provision_vace.sh` by hand in the Jupyter terminal (approach A) if the wrapper ever
  breaks.

## Testing / verification

1. Deploy a pod from the new template (24 GB+ GPU, e.g. 4090).
2. `tail -f /workspace/provision.log` until the ✅ summary.
3. Open port 8188, load the workflow JSON — zero "missing nodes" dialogs.
4. Run one short image-to-video generation end to end.
5. Stop and restart the pod — confirm fast boot and that everything still loads.

## Out of scope (v1)

- Network volume setup (documented as a future add-on for faster cold starts)
- Newer model stacks (WAN 2.2 etc.)
- Serverless/API deployment
- The old pod: it is not worth rescuing; terminate it once the new template works.
