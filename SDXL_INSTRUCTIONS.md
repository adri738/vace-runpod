# SDXL Forge on RunPod — quick guide

My own template for Stable Diffusion (Illustrious/SDXL) — replaces the
notebook-based ffxvs template. Forge auto-starts; my models auto-download.

## Start a pod

1. https://console.runpod.io → **Pods** → **Deploy**
2. GPU: RTX 4090 (24 GB is plenty for SDXL)
3. Template: **sdxl-forge** (mine)
4. Deploy **On-Demand**
5. First boot: ~10 min total (Forge unpacks itself ~3 min, then my models
   download ~10 GB). Check progress: Connect → **JupyterLab (8888)** →
   Terminal:

   ```
   tail -f /workspace/provision_sdxl.log
   ```

6. **If that file doesn't exist after ~5 min**, run the installer manually:

   ```
   cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_sdxl.sh -o provision_sdxl.sh && bash provision_sdxl.sh
   ```

7. Wait for `✅ SDXL provisioning finished — Forge is ready on port 3001.`

## Use Forge

1. Connect → **HTTP Service, port 3001**
2. Top bar: pick checkpoint `waiNSFWIllustrious_v120` and set
   **Clip skip = 2** (the Clip Skip box is already in the top bar —
   the script configures that automatically)
3. My resources: LoRA `extreme-sex-v1.0-illustriousxl` (Lora tab),
   embedding `lazypos` (just type `lazypos` in the prompt),
   ControlNet `controlnet-union-sdxl-1.0` (ControlNet section)
4. Forge log if something's wrong: `/workspace/logs/forge.log`
5. **Download generated images before terminating**
   (JupyterLab → `stable-diffusion-webui-forge/outputs`)

## Template settings (to rebuild from scratch)

| Setting | Value |
|---|---|
| Container Image | `ashleykza/forge:latest` |
| Container Disk | 30 GB |
| Volume Disk | 60 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `3001,8888` |
| Expose TCP Ports | `22` |
| Env `JUPYTER_LAB_PASSWORD` | (a password of my choosing) |

Container Start Command (one line, exactly):

```
bash -c 'nohup sh -c "sleep 20; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_sdxl.sh -o /workspace/provision_sdxl.sh; bash /workspace/provision_sdxl.sh --boot" > /workspace/provision-boot.log 2>&1 & /start.sh'
```

Notes:
- The old "update Forge with git pull" step is NOT needed on this image
  (it ships a working pinned Forge). If something ever requires it, add
  env var `UPDATE_FORGE` = `true` to the template.
- `lazypos` is an **embedding** (295 KB), not a LoRA — the script puts it
  in the right folder (`embeddings/`), unlike the old manual wget routine.
- Stop vs Terminate: same rules as the VACE pod (see INSTRUCTIONS.md).
