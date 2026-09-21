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

1. **Model source: private HuggingFace mirror.** Every model file is copied once to a
   private repo on the user's HF account — 14 files across both groups (see decision 9).
   The free HF plan includes 100 GB of private storage; the full mirror is 89.08 GB
   (82.97 GiB), which fits with ~11 GB of headroom. No paid plan required.
   **The mirror lives on a dedicated HF account, `adri73782`**, created for it on
   2026-09-21. The first mirror attempt went to her main account `marix64`, whose other
   private repos already used about half of that quota; the upload hit "Private repository
   storage limit reached" after 48 GB. The ~11 GB headroom therefore only holds while this
   account carries nothing but the mirror and the SageAttention wheel. Her usernames differ
   by service: GitHub `adri738`, HuggingFace `adri73782` (mirror) and `marix64` (everything
   else).
2. **Base image: official `runpod/comfyui`, pinned version.** Not the creator's image.
   The official image already publishes a CUDA 13 tag, so nothing is lost on that axis.
3. **Workflow JSONs travel through the private HF repo,** and the script places them in
   `ComfyUI/user/default/workflows/` so they appear in ComfyUI's saved-workflow list.
   They must never be committed to the public GitHub repo.
4. **Fork the single-maintainer node packs** to the user's GitHub account — 9 in group
   `base`, plus `ComfyUI-H3-FunControl` in group `controlnet`, 10 in all. The large,
   well-established packs are cloned from upstream at a pinned commit.
5. **Pod lifecycle: always terminate, never stop.** The user does not want to pay for
   idle volume storage. Every session re-downloads the models. This makes download
   throughput a first-class concern and means nothing may be cached on `/workspace`
   between sessions.
6. **All 10 base models download every time — no partial profile within `base`.** An
   earlier "lite" profile was considered and rejected: the user uses the
   reference-to-video mode, so `ref2va` (19.53 GB) cannot be skipped, which leaves only
   SAM3 and the T1 image VAE as candidates — 6.5 GB out of 77.46 GB. Not worth an env var
   that can silently leave a model missing months later. Decision 9's ControlNet toggle
   does not reopen this: it only ever *adds* a group on top of a complete `base`, so no
   setting can leave the main workflow short of a model.
7. **SageAttention in two stages** (see Architecture) rather than depending on the
   creator's prebuilt image.
8. **Additive, not a replacement.** The user keeps using the creator's template as a
   second option alongside this one. Nothing here may modify or depend on removing the
   creator's setup. Her existing `RUNBOOK_MINIMAX_RUNPOD.md` stays the guide for the
   creator's template, unchanged; `MINIMAX_INSTRUCTIONS.md` is the guide for this one.
   The workflow itself is identical under both, so `MINIMAX_INSTRUCTIONS.md` covers
   deploying and operating this template and points to the runbook for how to use the
   workflow, rather than duplicating it.
9. **Two own templates from one script.** The user wants her own MiniMax setup in two
   flavours, alongside the creator's: `minimax-h3`, without ControlNet (matching the
   creator's workflow), and `minimax-h3-controlnet`, which adds ControlNet. Both run the
   same `provision_minimax.sh` and read the same mirror; the only difference between the
   two RunPod templates is the env var `MINIMAX_CONTROLNET` (`false` / `true`). Every
   pack, model and workflow carries a group tag, `base` or `controlnet`, and the script
   installs `base` always and `controlnet` only when the variable is on. One script
   rather than two, so a fix lands in both at once and they cannot drift apart. The
   ControlNet template is a strict superset: it also carries the main workflow.

## Architecture

Three new files in the existing public repo `adri738/vace-runpod`:

| File | Role |
|---|---|
| `mirror_minimax.sh` | Run **once, ever**. Populates the private HF mirror with everything both templates need. |
| `provision_minimax.sh` | Run on **every boot**. Idempotent. Installs the groups the template asks for. |
| `MINIMAX_INSTRUCTIONS.md` | User-facing guide for both MiniMax templates, sibling of `SDXL_INSTRUCTIONS.md`. |

No new GitHub repo. The repo already hosts the VACE, SDXL and LLM-pod templates; these
two MiniMax templates join them, driven by one script.

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

Group `base` — installed by both templates. Sizes measured 2026-09-08 via HTTP HEAD
against `Aitrepreneur/FLX`.

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

Group `controlnet` — installed only by `minimax-h3-controlnet`. Sizes and sha256 read from
the HuggingFace tree API on 2026-09-21. These come from four different source repos, none
of them the creator's:

| File | Bytes | Source repo (path) | Destination, relative to the ComfyUI root |
|---|---|---|---|
| `minimax_h3_fun_controlnet_union_pruned_bf16.safetensors` | 4,222,169,456 | `Comfy-Org/MiniMax-H3` (`model_patches/`) | `models/controlnet/` |
| `depth_anything_v2_vitl.pth` | 1,341,395,338 | `depth-anything/Depth-Anything-V2-Large` | `custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Large/` |
| `yolox_l.onnx` | 216,746,733 | `yzd-v/DWPose` | `custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose/` |
| `dw-ll_ucoco_384_bs5.torchscript.pt` | 135,059,124 | `hr16/DWPose-TorchScript-BatchSize5` | `custom_nodes/comfyui_controlnet_aux/ckpts/hr16/DWPose-TorchScript-BatchSize5/` |
| **Total** | **5.51 GB** | | |

The destinations are not arbitrary and both were verified in source. The FunControl loader
lists and loads models via `folder_paths` category `"controlnet"`, so its model lives in
`models/controlnet/` even though HuggingFace stores it under `model_patches/`.
`comfyui_controlnet_aux` looks for `ckpts/<hf_repo_id>/<file>` before downloading anything,
so pre-placing the three preprocessor files there makes it use them with no network access.
Mirroring them, rather than letting the pack fetch them, keeps decision 1's independence and
avoids a re-fetch every session, since pods are always terminated.

Three of these four are **not safetensors** (`.pth`, `.onnx`, `.pt`), so the header check
described under error handling applies only to `.safetensors` files; the others are
validated by exact byte size alone, which still rejects every truncated download.

Totals: `base` 77.46 GB (83,169,189,972 bytes); both groups 82.97 GB (89,084,560,623 bytes,
89.08 GB decimal) — still inside the 100 GB free private tier.

Workflows, also tagged by group: `MINIMAX_H3_ULTRA_WORKFLOW-V3.json` is `base`;
`MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json` is `controlnet`. So `minimax-h3` gets the main
workflow and `minimax-h3-controlnet` gets both. (An earlier turbo workflow was in scope;
the user discarded it. The turbo LoRA above is still mirrored — it is selectable from within
the main workflow and is not tied to that file.) The main workflow references 9 of the base
model filenames; `taeh3.safetensors` is picked up automatically by ComfyUI for latent
previews. The ControlNet workflow additionally references the four `controlnet` files and
the node types `H3FunControlLoader`, `H3FunControlApply`, `DWPreprocessor` and
`DepthAnythingV2Preprocessor`.

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

All 13 packs above are group `base`. Group `controlnet` adds two more, by the same rule:

| Pack | Treatment |
|---|---|
| `wyzborrero/ComfyUI-H3-FunControl` | Single maintainer → **forked** to the user's account (the tenth fork) |
| `Fannovel16/comfyui_controlnet_aux` | Large, established → cloned from upstream at a pinned commit |

That makes 15 packs in all, 10 of them forks.

## `mirror_minimax.sh` requirements

Run once from a cheap CPU-only RunPod pod (or the first GPU pod), never at boot.

1. Requires a **write-scoped** HF token supplied interactively or via env var. It is used
   only here and is never stored in the template or the repo.
2. Creates the private HF repo (`adri73782/minimax-h3-ultra-v3` by default) if absent.
3. For each of the 14 files, both groups: download from that file's own source repo and
   path, verify size and hash match, upload to the private repo, and delete the local copy
   before moving to the next file so the pod disk never needs to hold all 83 GB at once.
   The mirror mirrors everything regardless of group — it is the single source for both
   templates. It is flat: every file sits at the repo root under its own filename, which
   is unique across all 14.
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

Which groups are active comes from `MINIMAX_CONTROLNET`: `true`, `1` or `yes`
(case-insensitive) activates `controlnet` on top of `base`; anything else, including
unset, means `base` only. The safe default is the smaller install.

**Phase 2 — node packs.** Clone or update the active packs (13, or 15 with ControlNet) at their pinned commits. Install
each pack's Python requirements with a **sanitized** requirements file: torch, torchvision,
torchaudio, xformers, triton, sageattention, numpy, transformers, tokenizers,
huggingface-hub, pillow and the `nvidia-*`/`cuda-*` families are filtered out so a custom
node can never replace the image's GPU runtime. (This idea is taken from the creator's
installer, which handles it correctly; the implementation is rewritten.)

**Phase 3 — models.** Download the active files (10, or 14 with ControlNet) from the private
HF mirror using the read-only token, in parallel, largest files first, each to its own
destination under the ComfyUI root. Prefer the `hf` CLI with Xet; fall back to `aria2c`,
then `curl`, then `wget`. Each file lands in a staging path, is validated, and only then is
atomically moved into place: exact byte size for every file, plus a safetensors header
parse for `.safetensors` files. Delete HF download caches afterward so nothing is stored
twice. Phase 3 runs after phase 2 on purpose — the preprocessor files go inside the
`comfyui_controlnet_aux` directory that phase 2 creates.

**Phase 4 — workflows.** Fetch the active workflow JSONs (1, or 2 with ControlNet) from the
mirror into `ComfyUI/user/default/workflows/`.

**Phase 5 — restart and verify.** Restart ComfyUI only if phase 2 changed anything. Then
confirm in the fresh startup log that every active pack actually loaded, and report any
that did not.

Log to `/workspace/provision_minimax.log`, with the same summary style as the existing
scripts.

## RunPod template settings

| Setting | Value |
|---|---|
| Container Image | `runpod/comfyui:1.4.7-cuda13.0` (pinned, not the floating `cuda13.0` tag) |
| Container Disk | 25 GB |
| Volume Disk | 150 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8188` (ComfyUI), `8888` (JupyterLab) |
| Expose TCP Ports | `22` |
| Env `HF_TOKEN` | fine-grained token, **read-only, scoped to the private mirror repo only** |
| Env `MINIMAX_HF_REPO` | `adri73782/minimax-h3-ultra-v3` (default name; any private repo id works) |
| Env `MINIMAX_CONTROLNET` | `false` on `minimax-h3`, `true` on `minimax-h3-controlnet` |

The table describes both RunPod templates. They are identical in every row except the
template name and `MINIMAX_CONTROLNET`.

Container Start Command (one line, identical on both templates):

```
{"entrypoint": ["bash", "-c", "nohup bash -c 'i=0; while [ ! -d /workspace/runpod-slim/ComfyUI/custom_nodes ] && [ $i -lt 180 ]; do sleep 5; i=$((i+1)); done; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o /workspace/provision_minimax.sh; bash /workspace/provision_minimax.sh --boot' > /workspace/provision-boot.log 2>&1 & exec /start.sh"]}
```

Volume sizing: 77.46 GB of models (82.97 GB with ControlNet) plus roughly 15 GB of ComfyUI,
its virtualenv and the node packs leaves ~50-55 GB for generated video on either template. Since pods are always terminated, this disk
is only billed while a pod runs — about $0.02/hour against ~$0.74/hour for the GPU — so the
extra headroom over a tighter 120 GB costs nothing meaningful and avoids running out of
space mid-session.

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

**Chosen by the user: RTX 6000 Ada (48 GB).** The 25.28 GB text encoder fits entirely in
VRAM, so there is no per-prompt offload to host RAM — the failure mode that rules out
24 GB cards.

System RAM is the secondary constraint, since ComfyUI parks inactive models there. RunPod's
RTX 6000 Ada configurations typically ship under 64 GB of host RAM; that should still be
fine given the models live in VRAM, but if long-video runs start swapping, host RAM is the
first thing to check. Verify the actual allocation at deploy time.

## Error handling

- No `set -e`. Failures accumulate in `FAILED` and are reported together at the end.
- Downloads are staged, validated, then atomically moved. Every file must match its exact
  byte size; `.safetensors` files must additionally have a parseable header. A network
  drop can never leave a corrupt model that ComfyUI half-loads.
- Re-running the script retries only what is missing.
- Node requirements are sanitized so no custom node can replace torch/CUDA/numpy.
- If ComfyUI must be restarted, wait for the new process to reach "Starting server" and
  verify node loading before declaring success.

## Testing / verification

Against a real pod, in this order:

1. `nvcc --version` — decides whether SageAttention stage 2 is viable. First task, 30 seconds.
2. Full run on a clean pod of `minimax-h3-controlnet` (the superset): 15 packs load, 14
   models validate, both workflows appear in ComfyUI's list, and the ControlNet workflow
   opens with no missing nodes. The `minimax-h3` template's narrower selection is proven by
   unit tests of the group filter rather than by a second paid GPU session.
3. Idempotence: re-run the script; it should skip everything and finish in under a minute.
4. Resume: interrupt a download mid-file, re-run, confirm it completes without corruption.
5. Real generation: load `MINIMAX_H3_ULTRA_WORKFLOW-V3.json` and render a short clip end to
   end, with `RF PATCH SAGE` enabled and `RF SPEEDUP` bypassed. This is the only test that
   actually counts.

## Reconnaissance results (pod session 1, 2026-09-21)

Measured on `runpod/comfyui:1.4.7-cuda13.0`, GPU pod, datacenter ca-mtl-1.

- **`nvcc` is present** — `/usr/local/cuda/bin/nvcc`, CUDA 13.0 V13.0.88. SageAttention stage 2
  is viable and stays in the design.
- **The entrypoint is `/start.sh`** — PID 1 is `/sbin/docker-init -- /start.sh`. The Container
  Start Command's `exec /start.sh` is correct.
- **The SAM3 nodes are ComfyUI core** — `comfy_extras/nodes_sam3.py`. No extra node pack.
- **ComfyUI's Python is `/workspace/runpod-slim/ComfyUI/.venv-cu128/bin/python`** — Python
  3.12.3, torch 2.10.0+cu130, CUDA 13.0, GPU available. The `cu128` in the name is legacy; its
  torch is CUDA 13, so it matches `nvcc`. It is the only venv: there is no `venv/` or `.venv/`,
  so the interpreter search must look for `.venv-cu130` / `.venv-cu128` and fail loudly if none
  is found, never fall back to the system `python3`.
- **`comfyui_args.txt` holds only its comment line** — no `--use-sage-attention`, so the
  workflow's `RF PATCH SAGE` group is the one route to SageAttention and stays enabled.
- **Tools:** `hf`, `curl`, `wget`, `sha256sum` present; `aria2c` absent (the download fallback
  chain skips it).
- **`/workspace` is a MooseFS network mount**; `df` reports the cluster, not the volume quota.
- **The mirror is Xet-backed**; observed throughput 40-400 MB/s, and uploads of files already
  present elsewhere on HF deduplicated to near-zero new data.

Mirror state after the session: `adri73782/minimax-h3-ultra-v3`, private, 17 paths at the root —
the 14 model files, the 2 workflow JSONs, and HF's automatic `.gitattributes`.

## Open questions to resolve during implementation

- Does `comfyui_controlnet_aux`'s sanitized requirements install a GPU-capable
  `onnxruntime`? Its DWPose wrapper falls back to CPU and warns when onnxruntime lacks
  acceleration providers — functional, but slow. Check the startup log for that warning.
- Does the v2++ SageAttention build succeed against torch 2.10 / CUDA 13? `nvcc` and torch agree,
  but the build itself has not been attempted. If it fails, the setup stays on v1.

## Out of scope (v1)

- Building a custom Docker image. Revisit only if SageAttention stage 2 proves impossible
  and v1 performance is unacceptable.
- Sourcing models from their true upstream authors instead of the mirror.
- RunPod Network Volumes. Rejected: the user terminates pods deliberately to avoid idle
  storage cost, and network volumes lock deployment to a single datacenter.
- Any redistribution of the paid workflow JSONs. They stay in the private mirror.
