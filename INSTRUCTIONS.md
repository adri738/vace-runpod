# How to run VACE on RunPod — quick guide

My own template. No Aitrepreneur template, no "Update ComfyUI" step, ever.

## Start a new pod (first time: ~20 min, mostly automatic)

1. Go to https://console.runpod.io → **Pods** → **Deploy**
2. GPU: at least 24 GB VRAM (RTX 4090 = best value; RTX 6000 Ada also fine)
3. Template: **vace-comfyui** (mine)
4. Deploy **On-Demand**
5. Wait ~5 minutes, then open the pod → **Connect** → **JupyterLab (port 8888)**
   → **File → New → Terminal**, and check progress with:

   ```
   tail -f /workspace/provision.log
   ```

6. **If it says "No such file or directory":** the auto-installer didn't start.
   Run it yourself (copy-paste the whole line, then Enter):

   ```
   cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_vace.sh -o provision_vace.sh && bash provision_vace.sh --restart-comfyui
   ```

7. Wait for: `✅ VACE provisioning finished — ComfyUI is ready.`
   (10–15 min on a new pod — it downloads ~23 GB of models.)
   Ignore the red "cupy" error in the middle — it's a harmless optional package.

## Use ComfyUI

1. Pod → **Connect** → **ComfyUI (port 8188)**. If the tab was already open,
   press refresh (F5).
2. Drag `VACE_IMAGE-TO-VIDEO_CONTROLNET.json` (from this folder on my PC)
   onto the page.
3. In the **GGUF VACE 14B** node, select `Wan2.1_14B_VACE-Q8_0.gguf`
   in the dropdown (one time per session — the saved workflow points at a
   file we don't use).
4. Upload image in **Load Image**, click **Queue**.
5. **Download finished videos to my PC before terminating the pod** —
   easiest via the JupyterLab file browser (output folder:
   `runpod-slim/ComfyUI/output`).

## Stop vs Terminate (money!)

- **Stop** = pod keeps its disk. Restart later takes ~2 min, everything still
  installed. You keep paying a small storage fee while stopped (~$0.20/day
  for 100 GB).
- **Terminate** = pod and disk deleted, zero cost. Next pod re-downloads the
  models (the 10–15 min first boot). Use this when I won't work for days.
- After **Stop → Start**: run the check in step 5 above; if ComfyUI is up
  and the workflow loads, nothing else needed.

## If something breaks

- **Red "Missing Node Types" when loading the workflow** → provisioning
  didn't finish. Run the command from step 6 above, wait for ✅, refresh
  the ComfyUI tab.
- **A file missing in a dropdown** → same command; it only re-downloads
  what's missing.
- **Never click "Update ComfyUI" in the Manager.** The base image is kept
  current by RunPod; updating by hand is what killed the old template.

## Reference

- My repo (script + full README): https://github.com/adri738/vace-runpod
- Template settings to rebuild from scratch: see the README in that repo.
- Security: keep `JUPYTER_PASSWORD` and `FILEBROWSER_PASSWORD` set as
  environment variables in the template.
