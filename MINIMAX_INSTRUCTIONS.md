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

1. https://console.runpod.io → **Pods** → **Deploy**
2. Filter: **CUDA 13.0** (the image needs it; an older driver crashes ComfyUI)
3. GPU: **RTX 6000 Ada (48 GB)**
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

## The one-time SageAttention wheel upload

First boot builds SageAttention v2++ in the background (~15–30 minutes)
while ComfyUI keeps running on v1. When the build finishes, the log prints
the exact command to upload the wheel to the mirror:

```
export HF_WRITE_TOKEN=hf_xxx
HF_TOKEN=$HF_WRITE_TOKEN hf upload adri73782/minimax-h3-ultra-v3 <wheel path> <mirror path>
```

Do this once, before terminating that pod — the wheel dies with the
volume otherwise. After it's uploaded, every future pod finds it on the
mirror and skips the 15–30 minute build entirely.

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
