# Running the VACE workflow — quick guide

What it does: **picture + motion video → new video** of the pictured subject
performing that motion. The ControlNet type decides *how* motion is copied.

## Once per session

1. Open ComfyUI (port 8188), drag in `VACE_IMAGE-TO-VIDEO_CONTROLNET.json`.
2. **GGUF VACE 14B** node → select `Wan2.1_14B_VACE-Q8_0.gguf`.

## Each generation

1. **Load Image** node → upload the subject picture (background is removed
   automatically).
2. **Load Video** node → upload the motion clip (a few seconds is ideal).
   The Video Info panel shows its fps/size/duration.
3. **Fast Groups Bypasser panel** → enable exactly ONE:
   - **Pose** — people & movement (dancing, gestures). Most forgiving.
   - **Depth** — copies 3D structure / camera feel. Scenes & objects.
   - **Canny** — copies hard outlines. Strictest shape match.
4. Positive prompt box → describe subject + scene. Leave negative as-is.
5. Blue boxes: **Width/Height** 720×720 default (use 480×480 for fast
   tests). Frames: 81 default (~3–5 s) — the model's sweet spot.
6. **Do NOT change the KSampler** (12 steps, CFG 1.0, uni_pc) — tuned for
   the CausVid LoRA. Raising CFG/steps breaks it.
7. **Queue**. First Pose/Depth run downloads small detector models (~1 min
   extra). Output appears in Video Combine (MP4, 30 fps).
8. Final render only: enable **VIDEO UPSCALER** and/or **VIDEO
   INTERPOLATION** (smoother, 48 fps) in the toggle panel and re-queue.
9. Download from JupyterLab → `runpod-slim/ComfyUI/output` before
   terminating the pod.

## Money-saving habits

- Experiment at 480×480, polish groups OFF; final render at full size with
  upscaler + interpolation ON.
- Seed is fixed → re-runs are comparable when you change one setting.
- Interpolation smooths motion but can't fix glitchy content; it ghosts on
  very fast motion.
