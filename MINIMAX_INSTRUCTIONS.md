# MiniMax H3 on RunPod — quick guide

Two templates, both mine, provisioning ComfyUI with MiniMax H3 video
generation from a private HuggingFace mirror. Pick one:

| Template | What it installs | Volume used |
|---|---|---|
| `minimax-h3` | the main workflow — same as the creator's | ~77 GB per session |
| `minimax-h3-controlnet` | the main workflow **and** the ControlNet one | ~83 GB per session |

The creator's own template is still a third option; my existing
`RUNBOOK_MINIMAX_RUNPOD.md` is the guide for that one.

> **⚠️ This pod is always terminated, never stopped.** Download every
> generated video before terminating — JupyterLab →
> `/workspace/runpod-slim/ComfyUI/output`. Nothing survives a terminate.

## Start a pod

> # 🚨 CHECK BEFORE YOU PRESS DEPLOY 🚨
>
> ## 1. CUDA filter = **13.0**
> Apply the filter **before** choosing the GPU, and confirm it is still
> showing on screen. Without it the pod can land on a machine with an older
> driver: everything installs, then ComfyUI dies with
> `The NVIDIA driver on your system is too old (found version 12080)`.
> Re-running the script does **not** fix that. Terminate the pod and
> redeploy with the filter.
>
> ## 2. Volume Disk = **150 GB**
> Look at the disk field on the deploy screen and confirm it says **150 GB**
> (mounted at `/workspace`). The models alone are ~89 GB. A smaller volume
> fills up mid-download and the provisioning fails.

1. https://console.runpod.io → **Pods** → **Deploy**
2. Filter: **CUDA 13.0** (the image needs it; an older driver crashes ComfyUI)
3. GPU: **L40S (48 GB)** — see the comparison below
4. Template: **minimax-h3** or **minimax-h3-controlnet** (mine)
5. Deploy **On-Demand**
6. First boot: roughly **15–25 minutes**, dominated by the models. Check
   progress: Connect → **JupyterLab (8888)** → Terminal:

   ```
   tail -f /workspace/provision_minimax.log
   ```

   The log's second line names the template (`template: minimax-h3` or
   `template: minimax-h3-controlnet`) — if it names the wrong one, the
   `MINIMAX_CONTROLNET` variable on the template is wrong.
7. Wait for `✅ MiniMax H3 provisioning finished`.

## GPU comparison

First clip of 10 s at 1280 x 736, measured on one pod per GPU. Each is a
single sample and includes model loading, so treat it as an estimate.

| GPU | Price/hr | Time per clip | Cost per clip |
|---|---|---|---|
| **L40S** | $1.09 | 676 s (~11 min) | **~$0.20** |
| RTX 6000 Ada (A6000 Ada) | $0.84 | 1892 s (~31 min) | ~$0.44 |
| A100 SXM | $1.59 | ~2150 s (~36 min), derived from balance | ~$0.95 |

The L40S is the fastest and the cheapest per clip. The A100 result was
probably slowed by the SageAttention build running in the background on
that first boot.

## If the log file never appears (~5 min)

First confirm the terminal sees the template's variable:

```
echo $MINIMAX_CONTROLNET
```

If that prints nothing on the ControlNet template, prefix the fallback
command with `MINIMAX_CONTROLNET=true`. Fallback (always works):

```
cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o provision_minimax.sh && bash provision_minimax.sh
```

## Using it

Connect → **HTTP Service, port 8188**. The workflows are already in the
workflow list (sidebar → **Workflows**) — no drag and drop needed.

For *how* to use them — groups, modes, prompting, what to leave enabled —
see `RUNBOOK_MINIMAX_RUNPOD.md` sections 3–5; the workflow itself is
identical under every template. Two toggles differ here specifically,
because of this script:

- **`RF PATCH SAGE`** — leave it **enabled**. This script does not pass
  `--use-sage-attention`, so the workflow group is the only route to it.
  Check with `cat /workspace/runpod-slim/comfyui_args.txt`.
- **`RF SPEEDUP`** — leave it **bypassed**.

## Template settings (to rebuild from scratch)

Both templates share this table. They differ in exactly two rows: the
template name and `MINIMAX_CONTROLNET`.

| Setting | Value |
|---|---|
| Container Image | `runpod/comfyui:1.4.7-cuda13.0` (pinned, not the floating `cuda13.0` tag) |
| Container Disk | 25 GB |
| Volume Disk | 150 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8188` (ComfyUI), `8888` (JupyterLab) |
| Expose TCP Ports | `22` |
| Env `HF_TOKEN` | fine-grained token, read-only, scoped to the private mirror repo only |
| Env `MINIMAX_HF_REPO` | `adri73782/minimax-h3-ultra-v3` |
| Env `MINIMAX_CONTROLNET` | `false` on `minimax-h3`, `true` on `minimax-h3-controlnet` |

Container Start Command (one line, exactly):

```
{"entrypoint": ["bash", "-c", "nohup bash -c 'i=0; while [ ! -d /workspace/runpod-slim/ComfyUI/custom_nodes ] && [ $i -lt 180 ]; do sleep 5; i=$((i+1)); done; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o /workspace/provision_minimax.sh; bash /workspace/provision_minimax.sh --boot' > /workspace/provision-boot.log 2>&1 & exec /start.sh"]}
```

It fetches from `main`, so the branch must be merged before a pod can use
it.

## SageAttention wheel

Already uploaded to the mirror (confirmed in the log of 2026-09-25:
`installed SageAttention 2++ from the mirror`). New pods download it and
skip the 15–30 minute build. You only need to upload a new wheel if the
image's Python, CUDA or torch version changes: the log will then say
`no usable prebuilt wheel for this image` and, once the background build
finishes, print the exact `hf upload` command. Run it before terminating
that pod — the wheel dies with the volume otherwise.

## If ComfyUI doesn't respond, or the log ends with "ComfyUI python not found"

The log ends like this:

```
❌ no ComfyUI virtualenv under /workspace/runpod-slim/ComfyUI — refusing to fall back to the system python
❌ phase 0: ComfyUI python not found
```

The script started before the image had finished creating ComfyUI's
virtualenv. Nothing is broken — just run it again in the JupyterLab
terminal (it only retries what is missing):

```
bash /workspace/provision_minimax.sh
```

Confirmed 2026-09-25: re-running it brought the pod back. If the ControlNet
template is in use and `echo $MINIMAX_CONTROLNET` prints nothing, prefix
the command with `MINIMAX_CONTROLNET=true`.

## If something goes wrong

**Symptom: red "missing node" boxes.**
Provisioning didn't finish. Check the end of
`/workspace/provision_minimax.log` for ❌ lines, re-run the fallback
command above, then refresh the ComfyUI browser tab.

**Symptom: red ControlNet nodes, specifically on the ControlNet template.**
The log's template line says `minimax-h3` instead of
`minimax-h3-controlnet` — the `MINIMAX_CONTROLNET` variable on the
template is wrong. Fix it, then re-run the fallback command.

**Symptom: a model is missing from a dropdown.**
Same fallback command — it re-downloads only what's missing.

**Symptom: `HF_TOKEN is not set` in the log.**
The template's `HF_TOKEN` env var is missing, or the token was revoked.

## Bumping a pin deliberately

- **Image version**: edit it in both templates' Container Image field.
- **A node pack's commit**: change that one line in
  `docs/minimax-node-pins.txt` and the matching line in `NODE_PACKS`
  inside `provision_minimax.sh`, then re-commit.

**Never regenerate the pin file wholesale** — that silently moves every
pack at once.
