# SDXL Forge on RunPod — quick guide

My own template for Stable Diffusion (Illustrious/SDXL) — replaces the
notebook-based ffxvs template. Forge auto-starts; my models auto-download.

## Start a pod

1. https://console.runpod.io → **Pods** → **Deploy**
2. GPU: RTX 4090 (24 GB is plenty for SDXL)
3. Template: **sdxl-forge** (mine)
4. Deploy **On-Demand**
5. First boot: ~15–20 min total (the image builds Forge onto the volume
   ~15 min, my models download ~10 GB alongside). Check progress:
   Connect → **JupyterLab (8888)** → Terminal:

   ```
   tail -f /workspace/provision_sdxl.log
   ```

6. **If that file doesn't exist after ~5 min**, run the installer manually:

   ```
   cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_sdxl.sh -o provision_sdxl.sh && bash provision_sdxl.sh --boot
   ```

7. Wait for `✅ SDXL provisioning finished — Forge is ready on port 7860.`

## Use Forge

1. Connect → **HTTP Service, port 7860** (log in with my WEBUI username/
   password if asked)
2. Top bar: pick checkpoint `waiNSFWIllustrious_v120` and set
   **Clip skip = 2** (the box is in the top bar — configured automatically;
   if it's missing, Settings tab → bottom → **Reload UI**)
3. My resources: LoRA `extreme-sex-v1.0-illustriousxl` (Lora tab),
   embedding `lazypos` (just type `lazypos` in the prompt),
   ControlNet `controlnet-union-sdxl-1.0` (ControlNet section)
4. **Download generated images before terminating**
   (JupyterLab → `/workspace/outputs`)

## Template settings (to rebuild from scratch)

| Setting | Value |
|---|---|
| Container Image | `dcainet/forge-min:latest` |
| Container Disk | 15 GB |
| Volume Disk | 60 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `7860` (Forge), `8888` (JupyterLab) |
| Expose TCP Ports | `22` |
| Env `JUPYTER_ENABLE` | `true` (Jupyter is OFF by default in this image) |
| Env `IDLE_ENABLE` | `false` (image auto-stops idle pods by default — off until I want that) |
| Env `WEBUI_USERNAME` | (my choice — protects the Forge page itself) |
| Env `WEBUI_PASSWORD` | (my choice) |

Container Start Command (one line, exactly):

```
bash -c 'nohup sh -c "sleep 20; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_sdxl.sh -o /workspace/provision_sdxl.sh; bash /workspace/provision_sdxl.sh --boot" > /workspace/provision-boot.log 2>&1 & /usr/local/bin/entrypoint.sh'
```

Notes:
- Forge paths in this image: webui `/workspace/forge/stable-diffusion-webui-forge`,
  models `/workspace/forge/models`, outputs `/workspace/outputs`.
- The old "update Forge with git pull" step is NOT needed; if ever required,
  set env `AUTO_UPDATE_FORGE` = `true` (built into the image).
- `lazypos` is an **embedding** (295 KB), not a LoRA — the script puts it in
  the embeddings folder, unlike the old manual wget routine.
- Idle auto-shutdown: once everything is proven, setting `IDLE_ENABLE`=`true`
  (and `IDLE_TIMEOUT_MINUTES`) makes the pod shut itself down when I forget
  it running — a credit saver, but know that it acts on its own.
- Stop vs Terminate: same rules as the VACE pod (see INSTRUCTIONS.md).
