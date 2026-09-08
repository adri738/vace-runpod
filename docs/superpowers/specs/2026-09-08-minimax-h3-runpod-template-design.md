# MiniMax H3 Ultra V3 RunPod Template — Design

**Date:** 2026-09-08
**Status:** Approved by user (pending written-spec review)

## Problem

The user runs Aitrepreneur's MiniMax H3 Ultra V3 workflow (video generation with
audio, long-video extend, and video inpainting) on RunPod. The creator's setup has
four dependencies on him personally:

1. His Docker image `aitrepreneur/comfyui:3.0.1-cuda13`.
2. His HuggingFace repo `Aitrepreneur/FLX`, source of all 10 model files (77.46 GB).
3. His workflow JSONs (paid Patreon content).
4. Two of the 13 required custom-node packs are his own GitHub repos
   (`ComfyUI-MiniMaxH3-T1-Latent`, `ComfyUI-H3-Motion-Context-MultiRef-V3`).

Any of these can disappear or change without warning. The same rot already happened
with his VACE template (see `2026-07-23-vace-runpod-template-design.md`), which is
why this repo exists. The user is a paying Patreon subscriber and this setup is for
her personal use only — nothing here is redistributed.

A relevant finding: the creator's installer looks for ComfyUI at
`/workspace/runpod-slim/ComfyUI` and reads `/workspace/runpod-slim/comfyui_args.txt`.
That is the layout of RunPod's official `runpod/comfyui` image. His image is a
derivative of it with SageAttention added. Moving to the official image is a return
to his own upstream, not a migration to unknown ground.

## Goal

A RunPod template the user owns end to end: official base image, her own provisioning
script, her own private model mirror, her own forks of the fragile node packs. Same
proven pattern as the existing VACE and SDXL templates in this repo — a
`provision_*.sh` fetched by the Container Start Command, idempotent, logging to
`/workspace`, with a matching `*_INSTRUCTIONS.md`.

## Decisions made with the user

1. **Model source: private HuggingFace mirror.** All 10 files are copied once to a
   private repo on the user's HF account. The free HF plan includes 100 GB of private
   storage; 77.46 GB fits with ~22 GB of headroom. No paid plan required.
2. **Base image: official `runpod/comfyui`, pinned version.** Not the creator's image.
   The official image already publishes a CUDA 13 tag, so nothing is lost on that axis.
3. **Workflow JSONs travel through the private HF repo,** and the script places them in
   `ComfyUI/user/default/workflows/` so they appear in ComfyUI's saved-workflow list.
   They must never be committed to the public GitHub repo.
4. **Fork the 9 single-maintainer node packs** to the user's GitHub account. The 4 large,
   well-established packs are cloned from upstream at a pinned commit.
5. **Pod lifecycle: always terminate, never stop.** The user does not want to pay for
   idle volume storage. Every session re-downloads the models. This makes download
   throughput a first-class concern and means nothing may be cached on `/workspace`
   between sessions.
6. **All 10 models download every time — no partial profile.** An earlier "lite" profile
   was considered and rejected: the user uses the reference-to-video mode, so `ref2va`
   (19.53 GB) cannot be skipped, which leaves only SAM3 and the T1 image VAE as
   candidates — 6.5 GB out of 77.46 GB. Not worth an env var that can silently leave a
   model missing months later.
7. **SageAttention in two stages** (see Architecture) rather than depending on the
   creator's prebuilt image.

## Architecture

Three new files in the existing public repo `adri738/vace-runpod`:

| File | Role |
|---|---|
| `mirror_minimax.sh` | Run **once, ever**. Populates the private HF mirror. |
| `provision_minimax.sh` | Run on **every boot**. Idempotent. Installs everything. |
| `MINIMAX_INSTRUCTIONS.md` | User-facing guide, sibling of `SDXL_INSTRUCTIONS.md`. |

No new GitHub repo. The existing repo already hosts two templates; this is the third.

### SageAttention strategy

The only real advantage of the creator's image is a precompiled SageAttention. There
are two versions and the distinction drives the design:

- **SageAttention 1.x** ships on PyPI as a `py3-none-any` wheel (v1.0.6). It is
  Triton-based, installs in seconds, needs no CUDA compiler, and works anywhere.
- **SageAttention 2/2++** (`thu-ml/SageAttention`) must be compiled with `nvcc`,
  taking 15-30 minutes. It is roughly 1.5-2x faster than v1 *at the attention step*;
  end-to-end gain on video is smaller, since attention is only part of total time.

Stage 1 (every boot): install v1 from PyPI. The workflow's `PathchSageAttentionKJ`
node works from the first boot.

Stage 2 (once, ever): compile v2++ in the background, then **upload the resulting
`.whl` to the private HF mirror**. Every later boot installs it from there in seconds.
Because the volume is destroyed on terminate, the mirror — not `/workspace` — is the
only durable cache available.

If the base image lacks `nvcc`, stage 2 is impossible and the setup stays on v1:
slower, not broken. Resolving this is the first implementation task.

Note for expectation-setting: most of this workflow's speed comes from the pruned int8
weights and the 4-step turbo LoRA, which are byte-identical to the creator's.
SageAttention is a secondary factor.

### Model inventory

Sizes measured 2026-09-08 via HTTP HEAD against `Aitrepreneur/FLX`.

| File | Size | ComfyUI folder |
|---|---|---|
| `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 25.28 GB | `text_encoders/` |
| `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 19.53 GB | `diffusion_models/` |
| `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | 19.53 GB | `diffusion_models/` |
| `minimax_h3_video_vae_fp16.safetensors` | 4.85 GB | `vae/` |
| `minimax_h3_t1_image_vae_step1597.safetensors` | 4.85 GB | `vae/` |
| `sam3.1_multiplex_fp16.safetensors` | 1.63 GB | `checkpoints/` |
| `minimax_h3_latent_upscaler_3d_fp16.safetensors` | 0.64 GB | `latent_upscale_models/` |
| `minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors` | 0.58 GB | `loras/` |
| `minimax_h3_audio_vae_fp32.safetensors` | 0.56 GB | `vae/` |
| `taeh3.safetensors` | 0.01 GB | `vae_approx/` |
| **Total** | **77.46 GB** | |

Both workflow JSONs (normal and turbo) reference the same node types and the same 9
model filenames; `taeh3.safetensors` is picked up automatically by ComfyUI for latent
previews.

### Node packs

Forked to the user's account (single-maintainer, fragile):

| Upstream |
|---|
| `xmarre/ComfyUI-Spectrum-MiniMax-H3` |
| `seesee75-commits/ComfyUI-MiniMaxH3-Director` |
| `Adudeguyman/ComfyUI-Fantastic-MiniMaxH3-PromptBuilder` |
| `BigStationW/ComfyUi-Scale-Image-to-Total-Pixels-Advanced` |
| `aitrepreneur/ComfyUI-MiniMaxH3-T1-Latent` |
| `Aitrepreneur/ComfyUI-H3-Motion-Context-MultiRef-V3` |
| `drozbay/MaskVidExperiments` |
| `Nekodificador/ComfyUI-NKD-Basic-Tools` |
| `LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler` |

Cloned from upstream at a pinned commit (large, established projects):
`ltdrdata/ComfyUI-Manager`, `rgthree/rgthree-comfy`, `kijai/ComfyUI-KJNodes`,
`Kosinkadink/ComfyUI-VideoHelperSuite`.

Every pack — forked or not — is pinned to an explicit commit, matching the philosophy
already used in `provision_vace.sh`. Pinning protects against breaking changes; forking
protects against deletion. Both are needed.

## `mirror_minimax.sh` requirements

Run once from a cheap CPU-only RunPod pod (or the first GPU pod), never at boot.

1. Requires a **write-scoped** HF token supplied interactively or via env var. It is used
   only here and is never stored in the template or the repo.
2. Creates the private HF repo (`adri738/minimax-h3-ultra-v3` by default) if absent.
3. For each of the 10 files: download from `Aitrepreneur/FLX`, upload to the private repo,
   verify size and hash match, delete the local copy before moving to the next file so the
   pod disk never needs to hold all 77 GB at once.
4. Skips files already present in the mirror with a matching size — safe to re-run after
   an interruption.
5. Uploads the two workflow JSONs when they are present locally (the user uploads these
   from her own machine; they are 1.7 MB each).
6. Prints a summary of what is now in the mirror versus what is missing.

Transfer runs datacenter-to-datacenter, not over the user's home connection: expect
15-25 minutes and under $0.05 of pod time.

## `provision_minimax.sh` requirements

Runs on every boot via the Container Start Command. Idempotent; every phase skips work
already done. Never aborts on first error — accumulates into a `FAILED` array and reports
a summary, matching `provision_vace.sh` and `provision_sdxl.sh`.

**Phase 0 — wait.** Block until the image has ComfyUI in place at
`/workspace/runpod-slim/ComfyUI` (bounded wait, then fail loudly).

**Phase 1 — SageAttention.** Try the prebuilt wheel from the HF mirror; else
`pip install sageattention` (v1) and, if `nvcc` exists, kick off the v2++ compile in the
background. ComfyUI must remain usable throughout.

**Phase 2 — node packs.** Clone or update all 13 packs at their pinned commits. Install
each pack's Python requirements with a **sanitized** requirements file: torch, torchvision,
torchaudio, xformers, triton, sageattention, numpy, transformers, tokenizers,
huggingface-hub, pillow and the `nvidia-*`/`cuda-*` families are filtered out so a custom
node can never replace the image's GPU runtime. (This idea is taken from the creator's
installer, which handles it correctly; the implementation is rewritten.)

**Phase 3 — models.** Download all 10 files from the private HF mirror using the read-only
token, in parallel, largest files first. Prefer the `hf` CLI with Xet; fall back to
`aria2c`, then `curl`, then `wget`. Each file lands in a staging path, is validated by
parsing its safetensors header against the file size, and only then is atomically moved
into place. Delete HF download caches afterward so the 77 GB is never stored twice.

**Phase 4 — workflows.** Fetch both JSONs from the mirror into
`ComfyUI/user/default/workflows/`.

**Phase 5 — restart and verify.** Restart ComfyUI only if phase 2 changed anything. Then
confirm in the fresh startup log that all 13 packs actually loaded, and report any that
did not.

Log to `/workspace/provision_minimax.log`, with the same summary style as the existing
scripts.

## RunPod template settings

| Setting | Value |
|---|---|
| Container Image | `runpod/comfyui:1.4.7-cuda13.0` (pinned, not the floating `cuda13.0` tag) |
| Container Disk | 25 GB |
| Volume Disk | 120 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8188` (ComfyUI), `8888` (JupyterLab) |
| Expose TCP Ports | `22` |
| Env `HF_TOKEN` | fine-grained token, **read-only, scoped to the private mirror repo only** |
| Env `MINIMAX_HF_REPO` | `adri738/minimax-h3-ultra-v3` (default name; any private repo id works) |

Container Start Command (one line):

```
{"entrypoint": ["bash", "-c", "nohup bash -c 'i=0; while [ ! -d /workspace/runpod-slim/ComfyUI/custom_nodes ] && [ $i -lt 180 ]; do sleep 5; i=$((i+1)); done; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o /workspace/provision_minimax.sh; bash /workspace/provision_minimax.sh --boot' > /workspace/provision-boot.log 2>&1 & exec /start.sh"]}
```

The image version is pinned for the same reason node commits are pinned: a RunPod update
should never be able to break a working pod unannounced. `MINIMAX_INSTRUCTIONS.md`
documents how to bump it deliberately.

The read-only, single-repo token scope matters because RunPod env vars are visible in the
template configuration. Worst case, a leak exposes read access to that one repo.

## Hardware guidance

The int8 text encoder is 25.28 GB on its own and the diffusion model is 19.53 GB. ComfyUI
loads them in turn, so peak VRAM is the larger of the two plus video latents.

| VRAM | Examples | Verdict |
|---|---|---|
| 24 GB | RTX 4090, L4 | Text encoder does not fit; offloads to system RAM every prompt. Not recommended. |
| 32 GB | RTX 5090 | Fits, barely. Fine for short clips; long video and latent upscale will be tight. |
| 48 GB | L40S, A6000, RTX 6000 Ada | Sweet spot. Real headroom for long video and inpainting. |
| 80-96 GB | H100, A100 80GB, RTX PRO 6000 | Comfortable, materially more expensive per hour. |

Also require **64 GB system RAM minimum** — ComfyUI offloads inactive models to host RAM,
and on RunPod the RAM allocation is tied to the chosen GPU, so it must be checked at
deploy time.

## Error handling

- No `set -e`. Failures accumulate in `FAILED` and are reported together at the end.
- Downloads are staged, validated (safetensors header vs file size), then atomically moved.
  A network drop can never leave a corrupt model that ComfyUI half-loads.
- Re-running the script retries only what is missing.
- Node requirements are sanitized so no custom node can replace torch/CUDA/numpy.
- If ComfyUI must be restarted, wait for the new process to reach "Starting server" and
  verify node loading before declaring success.

## Testing / verification

Against a real pod, in this order:

1. `nvcc --version` — decides whether SageAttention stage 2 is viable. First task, 30 seconds.
2. Full run on a clean pod: 13 packs load, 10 models validate, both workflows appear in
   ComfyUI's list.
3. Idempotence: re-run the script; it should skip everything and finish in under a minute.
4. Resume: interrupt a download mid-file, re-run, confirm it completes without corruption.
5. Real generation: load the turbo workflow and render a short clip end to end. This is the
   only test that actually counts.

## Open questions to resolve during implementation

- Does `runpod/comfyui:1.4.7-cuda13.0` include `nvcc`? Decides SageAttention stage 2.
- Is the image entrypoint still `/start.sh` at 1.4.7? It was at 1.2.x, per the VACE template.
- Which pack provides `SAM3_VideoTrack` / `SAM3_TrackToMask` / `SAM3_TrackPreview`? These are
  not clearly attributable to any of the 13 packs and may now be part of ComfyUI core. If so,
  one pack fewer.
- Does the private mirror repo get Xet-backed storage (affects download throughput)? HTTP
  fallback covers it either way.

## Out of scope (v1)

- Building a custom Docker image. Revisit only if SageAttention stage 2 proves impossible
  and v1 performance is unacceptable.
- Sourcing models from their true upstream authors instead of the mirror.
- RunPod Network Volumes. Rejected: the user terminates pods deliberately to avoid idle
  storage cost, and network volumes lock deployment to a single datacenter.
- Any redistribution of the paid workflow JSONs. They stay in the private mirror.
