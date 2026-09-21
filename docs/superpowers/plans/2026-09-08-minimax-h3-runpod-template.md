# MiniMax H3 Ultra V3 RunPod Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two RunPod templates the user owns end to end for the MiniMax H3 Ultra V3 workflow — `minimax-h3` without ControlNet and `minimax-h3-controlnet` with it — on an official base image, with her own provisioning script, her own private model mirror and her own forks of the fragile node packs. The creator's template stays available as a third option.

**Architecture:** Two bash scripts in the existing public repo `adri738/vace-runpod`. `mirror_minimax.sh` runs once ever and copies all 14 model files (89,084,560,623 bytes) from their five source repos into a private HuggingFace repo. `provision_minimax.sh` runs on every pod boot, fetched by the Container Start Command, and installs SageAttention plus the node packs, models and workflow JSONs of the active groups: `base` always (13 packs, 10 models, the main workflow), `controlnet` on top when `MINIMAX_CONTROLNET` is on (2 more packs, 4 more files, the ControlNet workflow). The two RunPod templates differ only in that variable. Both scripts are self-contained single files (they are fetched by `curl` at boot, so they cannot depend on sibling files), but expose their pure functions for local unit testing via a `BASH_SOURCE` guard.

**Amended 2026-09-21:** Tasks 5c and 5d were inserted and Tasks 6-10 updated for the two-template design. Tasks 1-5 and 5b were implemented against the original single-template design; 5c and 5d bring their artifacts forward.

**Tech Stack:** Bash 4+, git, curl/aria2c/wget, HuggingFace `hf` CLI, ComfyUI, RunPod. Tests are plain bash with a tiny hand-rolled assertion harness — no bats, no python (the user's Windows machine has no `python` on PATH).

**Spec:** `docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md`

## Global Constraints

- Base image: `runpod/comfyui:1.4.7-cuda13.0` — pinned, never the floating `cuda13.0` tag.
- ComfyUI root on the pod: `/workspace/runpod-slim/ComfyUI`.
- Volume Disk 150 GB, Container Disk 25 GB, mount path `/workspace`, HTTP ports `8188,8888`, TCP `22`.
- GPU: RTX 6000 Ada (48 GB VRAM).
- Private mirror repo: `adri73782/minimax-h3-ultra-v3`.
- Public GitHub repo: `adri738/vace-runpod`, branch `minimax-h3-template` during development; scripts must reach `main` before a pod can fetch them.
- **The two workflow JSONs are paid content and must NEVER be committed to the public GitHub repo.** They travel only through the private HF mirror. `.gitignore` must block them.
- The pod only ever holds a **read-only, single-repo** HF token. The write token is used by hand, once, and never stored in the template.
- Two templates, one script: `minimax-h3` (`MINIMAX_CONTROLNET=false`) and `minimax-h3-controlnet` (`MINIMAX_CONTROLNET=true`). Only `true`, `1` or `yes`, in any case, turns ControlNet on; anything else, unset included, means base only.
- Every node pack, model and workflow carries a group, `base` or `controlnet`. All 10 base models download on every boot of either template — there is no partial profile within `base`; `controlnet` only ever adds.
- Model validation: exact byte size for every file, plus a safetensors header parse for `.safetensors` files only — three ControlNet files are `.pth`/`.onnx`/`.pt`.
- Never probe a possibly-missing GitHub repo with plain `git`: on the user's Windows machine it pops up a GitHub account picker. Use the REST API via `curl`, or `GIT_TERMINAL_PROMPT=0 git -c credential.helper= ...`.
- Scripts never use `set -e`. Failures accumulate in a `FAILED` array and are reported in a final summary, matching `provision_vace.sh` and `provision_sdxl.sh`.
- All side effects live inside functions. Top level defines constants and functions only, so tests can source the script safely.

---

## File Structure

| Path | Responsibility |
|---|---|
| `provision_minimax.sh` (create) | Boot-time provisioner. Phases 0-5. Self-contained, sourceable. |
| `mirror_minimax.sh` (create) | One-time mirror population. Self-contained, sourceable. |
| `docs/minimax-node-pins.txt` (create) | Single source of truth for the 15 node packs, their pinned commits and their groups. Embedded verbatim into `provision_minimax.sh`; a test asserts the two never drift. |
| `tests/helpers.sh` (create) | Dependency-free assertion harness plus safetensors fixture builders. |
| `tests/test_provision_minimax.sh` (create) | Unit tests for the pure functions of `provision_minimax.sh`. |
| `tests/run_tests.sh` (create) | Runs every `tests/test_*.sh`, exits non-zero on any failure. |
| `MINIMAX_INSTRUCTIONS.md` (create) | User-facing guide for both MiniMax templates, sibling of `SDXL_INSTRUCTIONS.md`. |
| `README.md` (modify) | Add the two MiniMax templates to the intro. |
| `.gitignore` (modify) | Block `MINIMAX_*WORKFLOW*.json`. |

Two tasks (6 and 10) run on a real RunPod pod rather than locally. They are ordered so the user pays for exactly two pod sessions.

---

### Task 1: Fork the node packs and pin every commit

**Files:**
- Create: `docs/minimax-node-pins.txt`
- Test: manual verification command in Step 4

**Interfaces:**
- Produces: `docs/minimax-node-pins.txt`, 13 lines of `directory|clone_url|commit_sha`. Task 7 embeds this file verbatim into `provision_minimax.sh` as the `NODE_PACKS` block.

- [ ] **Step 1: Fork the 9 single-maintainer packs on GitHub**

Open each URL and click Fork (keep the default name, do not fork just the default branch — untick "Copy the main branch only" so tags stay available):

```
https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3
https://github.com/seesee75-commits/ComfyUI-MiniMaxH3-Director
https://github.com/Adudeguyman/ComfyUI-Fantastic-MiniMaxH3-PromptBuilder
https://github.com/BigStationW/ComfyUi-Scale-Image-to-Total-Pixels-Advanced
https://github.com/aitrepreneur/ComfyUI-MiniMaxH3-T1-Latent
https://github.com/Aitrepreneur/ComfyUI-H3-Motion-Context-MultiRef-V3
https://github.com/drozbay/MaskVidExperiments
https://github.com/Nekodificador/ComfyUI-NKD-Basic-Tools
https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler
```

The 4 remaining packs (`ltdrdata/ComfyUI-Manager`, `rgthree/rgthree-comfy`, `kijai/ComfyUI-KJNodes`, `Kosinkadink/ComfyUI-VideoHelperSuite`) are large, well-established projects and are cloned from upstream — do not fork them.

- [ ] **Step 2: Generate the pin file**

Run this from the repo root. It resolves the current default-branch commit of each repo and writes the manifest.

```bash
cd "C:/Users/Trabajo/OneDrive/Mis_Proyectos/Proyectos_Claude/template_runpod_aitrepeneur"

{
  echo "# dir|clone_url|commit — generated $(date +%F). Regenerate to update pins."
  for spec in \
    "ComfyUI-Manager|ltdrdata/ComfyUI-Manager" \
    "rgthree-comfy|rgthree/rgthree-comfy" \
    "ComfyUI-KJNodes|kijai/ComfyUI-KJNodes" \
    "ComfyUI-VideoHelperSuite|Kosinkadink/ComfyUI-VideoHelperSuite" \
    "ComfyUI-Spectrum-MiniMax-H3|adri738/ComfyUI-Spectrum-MiniMax-H3" \
    "ComfyUI-MiniMaxH3-Director|adri738/ComfyUI-MiniMaxH3-Director" \
    "ComfyUI-Fantastic-MiniMaxH3-PromptBuilder|adri738/ComfyUI-Fantastic-MiniMaxH3-PromptBuilder" \
    "ComfyUi-Scale-Image-to-Total-Pixels-Advanced|adri738/ComfyUi-Scale-Image-to-Total-Pixels-Advanced" \
    "ComfyUI-MiniMaxH3-T1-Latent|adri738/ComfyUI-MiniMaxH3-T1-Latent" \
    "ComfyUI-H3-Motion-Context-MultiRef|adri738/ComfyUI-H3-Motion-Context-MultiRef-V3" \
    "MaskVidExperiments|adri738/MaskVidExperiments" \
    "ComfyUI-NKD-Basic-Tools|adri738/ComfyUI-NKD-Basic-Tools" \
    "Comfyui_Minimax_h3_latent_Upscaler|adri738/Comfyui_Minimax_h3_latent_Upscaler"
  do
    dir="${spec%%|*}"
    repo="${spec#*|}"
    url="https://github.com/${repo}.git"
    sha="$(git ls-remote "$url" HEAD | awk '{print $1}')"
    if [ -z "$sha" ]; then
      echo "RESOLVE-FAILED|$url|" >&2
    else
      echo "${dir}|${url}|${sha}"
    fi
  done
} > docs/minimax-node-pins.txt

cat docs/minimax-node-pins.txt
```

Note the directory name for the MultiRef pack is `ComfyUI-H3-Motion-Context-MultiRef` while the repo is `...-MultiRef-V3`. That mismatch is deliberate — it is the directory name the creator's installer uses, and the pack may import itself by that name.

- [ ] **Step 3: Verify every line resolved**

```bash
grep -c '^[A-Za-z]' docs/minimax-node-pins.txt
grep -n 'RESOLVE-FAILED' docs/minimax-node-pins.txt || echo "no failures"
awk -F'|' '/^[A-Za-z]/ && length($3) != 40 {print "BAD SHA: " $0}' docs/minimax-node-pins.txt
```

Expected: `13`, then `no failures`, then no `BAD SHA` lines. If a fork URL 404s, the fork was not created — go back to Step 1.

- [ ] **Step 4: Confirm each pinned commit is actually fetchable**

```bash
while IFS='|' read -r dir url sha; do
  case "$dir" in \#*|"") continue ;; esac
  if git ls-remote "$url" | grep -q "^${sha}"; then
    echo "ok   $dir"
  else
    echo "FAIL $dir ($sha not on $url)"
  fi
done < docs/minimax-node-pins.txt
```

Expected: 13 `ok` lines, zero `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add docs/minimax-node-pins.txt
git commit -m "feat: pin the 13 MiniMax H3 custom-node packs

Nine single-maintainer packs now point at forks under adri738 so a
deleted upstream cannot break the template. The four large packs stay
on upstream. Every pack is pinned to an explicit commit."
```

---

### Task 2: Test harness and safetensors validation

**Files:**
- Create: `tests/helpers.sh`
- Create: `tests/run_tests.sh`
- Create: `tests/test_provision_minimax.sh`
- Create: `provision_minimax.sh`

**Interfaces:**
- Produces: `safetensors_ok <file> <expected_bytes>` — returns 0 when the file exists, its size matches `expected_bytes` exactly, and its safetensors header parses. Used by Task 8's `download_model`.
- Produces: the `provision_minimax.sh` skeleton with a `BASH_SOURCE` guard, so every later task appends functions to a file that tests can already source.
- Produces: `write_u64le`, `make_safetensors` test fixtures in `tests/helpers.sh`, reused by Task 3 and Task 4.

Validation strategy, so the implementer understands the choice: the file's exact byte size is known ahead of time from the HuggingFace tree API and is baked into the manifest, so a plain size comparison catches every truncation. Full sha256 verification is deliberately left to `mirror_minimax.sh` (once) rather than to every boot, because hashing 77 GB costs minutes of pod time per session.

- [ ] **Step 1: Write the test harness**

Create `tests/helpers.sh`:

```bash
#!/usr/bin/env bash
# Minimal assertion harness. No dependencies beyond bash + coreutils,
# because the developer machine (Windows/Git Bash) has no python.

TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1"
}

# assert_ok "name" command...   -> command must succeed
assert_ok() {
    local name="$1"; shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

# assert_fail "name" command... -> command must fail
assert_fail() {
    local name="$1"; shift
    if "$@"; then fail "$name (expected failure, got success)"; else pass "$name"; fi
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name"
        printf '       expected: [%s]\n' "$expected"
        printf '       actual:   [%s]\n' "$actual"
    fi
}

# Append a little-endian uint64 to a file.
write_u64le() {
    local value="$1" file="$2" i byte
    for ((i = 0; i < 8; i++)); do
        byte=$(( (value >> (i * 8)) & 255 ))
        printf "\\x$(printf '%02x' "$byte")" >> "$file"
    done
}

# make_safetensors <path> [extra_trailing_bytes]
# Produces a structurally valid safetensors file of 66 bytes (+ extras).
make_safetensors() {
    local path="$1" extra="${2:-0}" i
    local header='{"t":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}'

    : > "$path"
    write_u64le "${#header}" "$path"
    printf '%s' "$header" >> "$path"
    printf 'ABCD' >> "$path"
    for ((i = 0; i < extra; i++)); do printf 'X' >> "$path"; done
}

finish() {
    printf '\n%d test(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
    [[ "$TESTS_FAILED" -eq 0 ]]
}
```

Create `tests/run_tests.sh`:

```bash
#!/usr/bin/env bash
# Runs every test file. Exits non-zero if any of them fails.
cd "$(dirname "$0")/.." || exit 1

status=0
for t in tests/test_*.sh; do
    printf '\n=== %s ===\n' "$t"
    bash "$t" || status=1
done

if [[ "$status" -eq 0 ]]; then
    printf '\nALL TESTS PASSED\n'
else
    printf '\nSOME TESTS FAILED\n'
fi
exit "$status"
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_provision_minimax.sh`:

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
source tests/helpers.sh
source provision_minimax.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "-- safetensors_ok --"

make_safetensors "$TMP/good.safetensors"
assert_ok   "valid file with matching size"      safetensors_ok "$TMP/good.safetensors" 66
assert_fail "valid file with wrong size"         safetensors_ok "$TMP/good.safetensors" 67

head -c 40 "$TMP/good.safetensors" > "$TMP/trunc.safetensors"
assert_fail "truncated download"                 safetensors_ok "$TMP/trunc.safetensors" 66

printf '<html><body>404 Not Found</body></html>' > "$TMP/html.safetensors"
assert_fail "HTML error page saved as a model"   safetensors_ok "$TMP/html.safetensors" 39

: > "$TMP/empty.safetensors"
assert_fail "zero-byte file"                     safetensors_ok "$TMP/empty.safetensors" 0

assert_fail "missing file"                       safetensors_ok "$TMP/nope.safetensors" 66

# The two cases below matter more than they look. Every case above is
# rejected by the size check or the header-length bounds, so none of them
# ever forces the last two guards to reject anything. Without these, both
# guards could be silently turned into no-ops and the suite would stay
# green. Each passes its own file size to safetensors_ok so that the size
# check cannot be what does the rejecting.
#
# Each fixture must violate ONLY the guard it targets. That is why the
# broken-brace header below keeps "data_offsets" intact: a header of plain
# filler would be rejected by the data_offsets grep instead, leaving the
# brace guard untested and a no-op regression in it invisible.

header_bad='X"t":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}'
: > "$TMP/nobrace.safetensors"
write_u64le "${#header_bad}" "$TMP/nobrace.safetensors"
printf '%s' "$header_bad" >> "$TMP/nobrace.safetensors"
printf 'ABCD' >> "$TMP/nobrace.safetensors"
assert_fail "header does not start with a brace" \
    safetensors_ok "$TMP/nobrace.safetensors" "$(stat -c%s "$TMP/nobrace.safetensors")"

header_nooffsets='{"t":{"dtype":"F16","shape":[2],"no_offsets":[0,4]}}'
: > "$TMP/nooffsets.safetensors"
write_u64le "${#header_nooffsets}" "$TMP/nooffsets.safetensors"
printf '%s' "$header_nooffsets" >> "$TMP/nooffsets.safetensors"
printf 'ABCD' >> "$TMP/nooffsets.safetensors"
assert_fail "header without data_offsets" \
    safetensors_ok "$TMP/nooffsets.safetensors" "$(stat -c%s "$TMP/nooffsets.safetensors")"

finish
```

- [ ] **Step 3: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: FAIL — `provision_minimax.sh: No such file or directory`.

- [ ] **Step 4: Write the minimal implementation**

Create `provision_minimax.sh`:

```bash
#!/usr/bin/env bash
# provision_minimax.sh — MiniMax H3 Ultra V3 provisioning for RunPod.
#
# Runs on every boot via the Container Start Command. Idempotent: every
# phase skips work that is already done. Never aborts on the first error —
# problems accumulate in FAILED and are reported in a final summary.
#
# Usage:
#   bash provision_minimax.sh          # manual run from a Jupyter terminal
#   bash provision_minimax.sh --boot   # boot mode: waits for ComfyUI first
#
# Design note: every side effect lives inside a function so that the test
# suite can source this file without touching the machine.

set -uo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
MIRROR_REPO="${MINIMAX_HF_REPO:-adri73782/minimax-h3-ultra-v3}"
LOG="${MINIMAX_LOG:-/workspace/provision_minimax.log}"
STAGING="${MINIMAX_STAGING:-/workspace/.minimax_staging}"
MODEL_PARALLEL="${MINIMAX_PARALLEL:-3}"

FAILED=()

log() { printf '%s\n' "$*"; }

# safetensors_ok <file> <expected_bytes>
#
# The exact byte size of every model is known from the HuggingFace tree API
# and baked into MODEL_MANIFEST, so an exact size match already rules out
# every truncated download. The header parse additionally rejects files that
# are the right size but not safetensors at all (an HTML error page, say).
safetensors_ok() {
    local file="$1" expected="$2"
    local actual header_len first

    [[ -f "$file" ]] || return 1

    actual="$(stat -c%s "$file" 2>/dev/null)" || return 1
    [[ "$actual" == "$expected" ]] || return 1

    header_len="$(head -c 8 "$file" | od -An -tu8 | tr -d '[:space:]')"
    [[ "$header_len" =~ ^[0-9]+$ ]] || return 1
    (( header_len > 2 && header_len < 104857600 )) || return 1
    (( 8 + header_len <= actual )) || return 1

    first="$(head -c 9 "$file" | tail -c 1)"
    [[ "$first" == "{" ]] || return 1

    head -c "$(( 8 + header_len ))" "$file" | tail -c "$header_len" \
        | grep -q '"data_offsets"'
}

main() {
    log "provision_minimax.sh: no phases implemented yet"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 5: Run the tests and make sure they pass**

```bash
bash tests/run_tests.sh
```

Expected: `8 test(s), 0 failure(s)` then `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add tests/helpers.sh tests/run_tests.sh tests/test_provision_minimax.sh provision_minimax.sh
git commit -m "feat: add test harness and safetensors validation

Validates a downloaded model by exact byte size plus a header parse.
Sizes come from the HuggingFace tree API and are baked into the
manifest, so size equality already catches every truncation; sha256
verification stays in the mirror script so boots do not pay for it."
```

---

### Task 3: Requirements sanitizer

**Files:**
- Modify: `provision_minimax.sh` (add `sanitize_requirements`)
- Modify: `tests/test_provision_minimax.sh` (add a test block)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `sanitize_requirements <input_file> <output_file>` — copies a `requirements.txt` while dropping any line that would install or replace a runtime-critical package. Used by Task 7's phase 2.

The danger this defends against: a custom node whose `requirements.txt` pins `torch==2.3` will silently downgrade the image's CUDA 13 build and break every GPU operation on the pod. The filter must drop `torch` but keep `torchsde`, which is a legitimate and unrelated dependency.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_provision_minimax.sh`, immediately before the final `finish` call:

```bash
echo "-- sanitize_requirements --"

cat > "$TMP/req.txt" <<'REQ'
# a comment line
torch>=2.4.0
torchvision
torchaudio==2.4.0
torchsde
xformers
triton
sageattention
numpy<2
transformers==4.44.0
tokenizers
huggingface-hub
huggingface_hub>=0.24
hf-xet
pillow
accelerate
safetensors
nvidia-cublas-cu12==12.4.5.8
cuda-python
comfyui-frontend-package
imageio-ffmpeg
opencv-python-headless
scipy

REQ

sanitize_requirements "$TMP/req.txt" "$TMP/clean.txt"

kept_present() { grep -qxF "$1" "$TMP/clean.txt"; }
line_absent()  { ! grep -qiE "^[[:space:]]*$1([<>=!~[]|[[:space:]]*$)" "$TMP/clean.txt"; }

assert_ok   "keeps torchsde"                kept_present "torchsde"
assert_ok   "keeps imageio-ffmpeg"          kept_present "imageio-ffmpeg"
assert_ok   "keeps opencv-python-headless"  kept_present "opencv-python-headless"
assert_ok   "keeps scipy"                   kept_present "scipy"
assert_ok   "keeps comments"                kept_present "# a comment line"

assert_ok   "drops torch"                   line_absent "torch"
assert_ok   "drops torchvision"             line_absent "torchvision"
assert_ok   "drops torchaudio"              line_absent "torchaudio"
assert_ok   "drops xformers"                line_absent "xformers"
assert_ok   "drops triton"                  line_absent "triton"
assert_ok   "drops sageattention"           line_absent "sageattention"
assert_ok   "drops numpy"                   line_absent "numpy"
assert_ok   "drops transformers"            line_absent "transformers"
assert_ok   "drops tokenizers"              line_absent "tokenizers"
assert_ok   "drops huggingface-hub"         line_absent "huggingface-hub"
assert_ok   "drops huggingface_hub"         line_absent "huggingface_hub"
assert_ok   "drops hf-xet"                  line_absent "hf-xet"
assert_ok   "drops pillow"                  line_absent "pillow"
assert_ok   "drops accelerate"              line_absent "accelerate"
assert_ok   "drops safetensors"             line_absent "safetensors"
assert_ok   "drops nvidia-* wheels"         line_absent "nvidia-cublas-cu12"
assert_ok   "drops cuda-python"             line_absent "cuda-python"
assert_ok   "drops comfyui-frontend-package" line_absent "comfyui-frontend-package"

# An all-blocked file must produce an empty result, not an error.
printf 'torch\nnumpy\n' > "$TMP/allblocked.txt"
sanitize_requirements "$TMP/allblocked.txt" "$TMP/allblocked.out"
assert_eq "all-blocked file yields no lines" "0" "$(grep -c . "$TMP/allblocked.out")"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: FAIL — `sanitize_requirements: command not found`.

- [ ] **Step 3: Write the minimal implementation**

Add to `provision_minimax.sh`, after `safetensors_ok`:

```bash
# sanitize_requirements <input> <output>
#
# Strips packages that belong to the image's GPU runtime. A custom node
# pinning "torch==2.3" would silently replace the CUDA 13 build and break
# every GPU operation on the pod. The name alternation is anchored so that
# "torch" is dropped while "torchsde" — a real, unrelated dependency — is
# kept. The nvidia-/cuda- families need their own prefix branch because
# their real names carry suffixes (nvidia-cublas-cu12).
sanitize_requirements() {
    local input="$1" output="$2"

    grep -Eiv \
        '^[[:space:]]*((torch|torchvision|torchaudio|xformers|triton|sageattention|numpy|transformers|tokenizers|huggingface[-_]hub|hf[-_]xet|pillow|accelerate|safetensors|comfyui[-_]frontend[-_]package|comfyui[-_]workflow[-_]templates|comfyui[-_]embedded[-_]docs)|(nvidia|cuda)[-_][A-Za-z0-9._-]*)([[:space:]]*[<>=!~[].*)?[[:space:]]*$' \
        "$input" > "$output" || true
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
bash tests/run_tests.sh
```

Expected: `32 test(s), 0 failure(s)` then `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add provision_minimax.sh tests/test_provision_minimax.sh
git commit -m "feat: sanitize custom-node requirements before install

Drops torch/CUDA/numpy-family pins so a custom node can never replace
the image's GPU runtime, while keeping legitimate lookalikes such as
torchsde."
```

---

### Task 4: Model manifest

**Files:**
- Modify: `provision_minimax.sh` (add `MODEL_MANIFEST` and `manifest_lines`)
- Modify: `tests/test_provision_minimax.sh` (add a test block)

**Interfaces:**
- Produces: `MODEL_MANIFEST` — a newline-separated string of `filename|comfyui_subdir|exact_bytes`.
- Produces: `manifest_lines` — echoes the manifest with comments and blank lines removed. Task 8's download loop reads from it.

Sizes were read from `https://huggingface.co/api/models/Aitrepreneur/FLX/tree/main?recursive=1` on 2026-09-08. They are exact file sizes in bytes, not rounded.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_provision_minimax.sh`, immediately before the final `finish` call:

```bash
echo "-- model manifest --"

assert_eq "manifest has 10 entries" "10" "$(manifest_lines | grep -c .)"

assert_eq "manifest totals 83169189972 bytes" "83169189972" \
    "$(manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"

assert_eq "no duplicate filenames" "0" \
    "$(manifest_lines | cut -d'|' -f1 | sort | uniq -d | grep -c .)"

assert_eq "every line has three fields" "0" \
    "$(manifest_lines | awk -F'|' 'NF != 3' | grep -c .)"

assert_eq "every size is a positive integer" "0" \
    "$(manifest_lines | awk -F'|' '$3 !~ /^[1-9][0-9]*$/' | grep -c .)"

assert_eq "every subdir is a known ComfyUI models folder" "0" \
    "$(manifest_lines | awk -F'|' '
        $2 != "text_encoders" && $2 != "diffusion_models" && $2 != "vae" &&
        $2 != "checkpoints" && $2 != "loras" && $2 != "vae_approx" &&
        $2 != "latent_upscale_models"' | grep -c .)"

assert_eq "text encoder is present at its exact size" "27141342152" \
    "$(manifest_lines | awk -F'|' '$1 == "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" {print $3}')"

assert_eq "reference-to-video model is present" "1" \
    "$(manifest_lines | grep -c '^minimax_h3_ref2va_pruned_int8_convrot\.safetensors|diffusion_models|')"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: FAIL — `manifest_lines: command not found`.

- [ ] **Step 3: Write the minimal implementation**

Add to `provision_minimax.sh`, after `sanitize_requirements`:

```bash
# filename|comfyui models subdirectory|exact size in bytes
#
# Sizes read from the HuggingFace tree API on 2026-09-08. They are the
# contract that safetensors_ok checks each download against, so they must
# never be edited by hand — regenerate them from the API if the mirror
# content ever changes.
MODEL_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|text_encoders|27141342152
minimax_h3_fl2va_pruned_int8_convrot.safetensors|diffusion_models|20970379616
minimax_h3_ref2va_pruned_int8_convrot.safetensors|diffusion_models|20970379616
minimax_h3_t1_image_vae_step1597.safetensors|vae|5207808784
minimax_h3_video_vae_fp16.safetensors|vae|5207808496
sam3.1_multiplex_fp16.safetensors|checkpoints|1745546848
minimax_h3_latent_upscaler_3d_fp16.safetensors|latent_upscale_models|690592672
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|loras|620285592
minimax_h3_audio_vae_fp32.safetensors|vae|605254808
taeh3.safetensors|vae_approx|9791388
'

WORKFLOW_FILES='
MINIMAX_H3_ULTRA_WORKFLOW-V3.json
MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json
'

manifest_lines() {
    printf '%s\n' "$MODEL_MANIFEST" | grep -vE '^[[:space:]]*(#|$)'
}

workflow_lines() {
    printf '%s\n' "$WORKFLOW_FILES" | grep -vE '^[[:space:]]*(#|$)'
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
bash tests/run_tests.sh
```

Expected: `40 test(s), 0 failure(s)` then `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add provision_minimax.sh tests/test_provision_minimax.sh
git commit -m "feat: add the MiniMax H3 model manifest

Ten files, 83,169,189,972 bytes total, with exact sizes from the
HuggingFace tree API so downloads can be validated without hashing
77 GB on every boot."
```

---

### Task 5: The one-time mirror script

**Files:**
- Create: `mirror_minimax.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the same `filename|subdir|bytes` manifest format as Task 4, duplicated here because both scripts must stay standalone single files.
- Produces: a populated private HF repo. Task 8's `fetch_mirror_file` reads from it.

This script is verified by running it in Task 6, not by unit tests — it is almost entirely network I/O. What is unit-testable in it (the manifest) is already covered by Task 4.

- [ ] **Step 1: Block the paid workflow JSONs from ever being committed**

Append to `.gitignore`:

```
# Paid Patreon content — lives only in the private HF mirror, never here
MINIMAX_*WORKFLOW*.json
```

Verify the rule works. Do **not** copy a real workflow JSON into the repo to test this — even
briefly, that puts paid content inside the working tree. `git check-ignore` answers the same
question from the filename alone:

```bash
git check-ignore -v MINIMAX_H3_ULTRA_WORKFLOW-V3.json
git check-ignore -v MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json
```

Expected: both print the `.gitignore` line number and the matching pattern, and exit 0. No
output means the rule does not match — fix the pattern.

- [ ] **Step 2: Write the mirror script**

Create `mirror_minimax.sh`:

```bash
#!/usr/bin/env bash
# mirror_minimax.sh — populate the private MiniMax H3 model mirror.
#
# RUN THIS ONCE, EVER, from a RunPod pod (a cheap CPU-only pod is fine).
# It copies the 10 model files from the public source repo into the user's
# own private HuggingFace repo, verifying sha256 on the way, and uploads
# the two workflow JSONs if they are present locally.
#
# The write token is used here and only here. It must never be stored in
# the RunPod template.
#
# Usage:
#   export HF_WRITE_TOKEN=hf_xxx
#   bash mirror_minimax.sh
#
# Re-running is safe: files already in the mirror at the right size are
# skipped, so an interrupted run resumes where it stopped.

set -uo pipefail

SOURCE_REPO="${MINIMAX_SOURCE_REPO:-Aitrepreneur/FLX}"
MIRROR_REPO="${MINIMAX_HF_REPO:-adri73782/minimax-h3-ultra-v3}"
WORK="${MINIMAX_MIRROR_WORK:-/workspace/.minimax_mirror}"

FAILED=()

log() { printf '%s\n' "$*"; }

# filename|expected bytes|sha256
MIRROR_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|27141342152|bc2ced0fbea64757fa9acddccfc0b3f4819d1dcf1da6c124d690d368be283923
minimax_h3_fl2va_pruned_int8_convrot.safetensors|20970379616|e889202c41dafb67b10d67b97f0d8541508036a6090af23425a5c2615d03c47a
minimax_h3_ref2va_pruned_int8_convrot.safetensors|20970379616|9255f52b6677845ad238f20dfaafa94727053694127ab7f255c048f0f9365779
minimax_h3_t1_image_vae_step1597.safetensors|5207808784|6c3d0bfa055986a803a566a862fcde283a1e63db62829e5ef4a2a5aebf50bb86
minimax_h3_video_vae_fp16.safetensors|5207808496|7c1f131492e7eddacaac9069a61b81bdd39de5cc96561e677c5eab1cdce5e522
sam3.1_multiplex_fp16.safetensors|1745546848|9ba99c92703c2e8b4f47de2d34a539bb8e18923049e238b780d70dbe6368eb03
minimax_h3_latent_upscaler_3d_fp16.safetensors|690592672|043e5a48e161610ef6c3ea974645220354d06fa618abca15f76d084812eb55c2
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|620285592|7098acf3ee75028fd9fcd948f50fcc8d995057fabb76f86bd3ca2c0ffc58e409
minimax_h3_audio_vae_fp32.safetensors|605254808|8e505d95dd1561d47abd43d4238fd40d9bb1ae9e147ed0a4cba778d76ae4db48
taeh3.safetensors|9791388|f0f60fa072089997f817402098c2fd90777cb2660dd79cf5df42fc1e3e08e527
'

mirror_manifest_lines() {
    printf '%s\n' "$MIRROR_MANIFEST" | grep -vE '^[[:space:]]*(#|$)'
}

require_tools() {
    local missing=0 t
    for t in hf curl; do
        command -v "$t" >/dev/null 2>&1 || { log "missing required tool: $t"; missing=1; }
    done
    if ! command -v sha256sum >/dev/null 2>&1; then
        log "missing required tool: sha256sum"
        missing=1
    fi
    [[ "$missing" -eq 0 ]]
}

# Size of a file already in the mirror, or empty if absent.
mirror_size() {
    local name="$1"
    curl -sIL --max-time 60 \
        -H "Authorization: Bearer ${HF_WRITE_TOKEN}" \
        "https://huggingface.co/${MIRROR_REPO}/resolve/main/${name}" \
        | tr -d '\r' \
        | grep -i '^x-linked-size:' \
        | tail -1 \
        | awk '{print $2}'
}

copy_one() {
    local name="$1" bytes="$2" want_sha="$3"
    local local_file="$WORK/$name"
    local present got_sha got_size

    present="$(mirror_size "$name")"
    if [[ "$present" == "$bytes" ]]; then
        log " [SKIP] $name already mirrored"
        return 0
    fi

    log " • downloading $name ($bytes bytes)"
    rm -rf "$WORK"
    mkdir -p "$WORK"

    # Every failure path below deletes the local copy before returning. The
    # sweep at the top of the next copy_one would eventually do it, but only
    # if there is a next one: a run killed here (pod evicted, OOM, network
    # drop) would otherwise strand up to 27 GB on the volume until the user
    # runs the script again. On a 60 GB recon pod that is half the disk.
    if ! hf download "$SOURCE_REPO" "$name" --local-dir "$WORK" >/dev/null; then
        rm -f "$local_file"
        FAILED+=("download: $name")
        return 1
    fi

    got_size="$(stat -c%s "$local_file" 2>/dev/null)"
    if [[ "$got_size" != "$bytes" ]]; then
        log "   ✗ size mismatch: expected $bytes, got ${got_size:-none}"
        rm -f "$local_file"
        FAILED+=("size: $name")
        return 1
    fi

    log "   verifying sha256 (this is the only time we pay for it)"
    got_sha="$(sha256sum "$local_file" | awk '{print $1}')"
    if [[ "$got_sha" != "$want_sha" ]]; then
        log "   ✗ sha256 mismatch"
        log "     expected $want_sha"
        log "     got      $got_sha"
        rm -f "$local_file"
        FAILED+=("sha256: $name")
        return 1
    fi

    log "   uploading to $MIRROR_REPO"
    if ! HF_TOKEN="$HF_WRITE_TOKEN" hf upload "$MIRROR_REPO" "$local_file" "$name" \
        --repo-type model >/dev/null; then
        rm -f "$local_file"
        FAILED+=("upload: $name")
        return 1
    fi

    rm -f "$local_file"
    log "   ✓ $name mirrored"
}

# The workflow filenames live in a constant rather than inline in the loop, so
# a test can check this list against WORKFLOW_FILES in provision_minimax.sh. A
# name that goes stale in only one of the two scripts is the same drift the
# model manifest test already guards against — and it has happened once.
MIRROR_WORKFLOW_FILES='
MINIMAX_H3_ULTRA_WORKFLOW-V3.json
MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json
'

mirror_workflow_lines() {
    printf '%s\n' "$MIRROR_WORKFLOW_FILES" | grep -vE '^[[:space:]]*(#|$)'
}

upload_workflows() {
    local f
    log "──── workflow JSONs ────"
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        if [[ ! -f "$f" ]]; then
            log " [SKIP] $f not present in $(pwd) — upload it later from your PC"
            continue
        fi
        if HF_TOKEN="$HF_WRITE_TOKEN" hf upload "$MIRROR_REPO" "$f" "$f" \
            --repo-type model >/dev/null; then
            log " ✓ $f uploaded"
        else
            FAILED+=("upload: $f")
        fi
    done <<< "$(mirror_workflow_lines)"
}

main() {
    local name bytes sha

    if [[ -z "${HF_WRITE_TOKEN:-}" ]]; then
        log "HF_WRITE_TOKEN is not set."
        log "Create a write token at https://huggingface.co/settings/tokens, then:"
        log "  export HF_WRITE_TOKEN=hf_xxx"
        exit 1
    fi

    require_tools || exit 1

    log "════ mirroring $SOURCE_REPO -> $MIRROR_REPO ════"

    if ! HF_TOKEN="$HF_WRITE_TOKEN" hf repo create "$MIRROR_REPO" \
        --repo-type model --private 2>/dev/null; then
        log "(repo already exists, or creation was refused — continuing)"
    fi

    mkdir -p "$WORK"

    while IFS='|' read -r name bytes sha; do
        [[ -n "$name" ]] || continue
        copy_one "$name" "$bytes" "$sha"
    done <<< "$(mirror_manifest_lines)"

    upload_workflows

    rm -rf "$WORK"

    log "──────────────────────────────────"
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        log "✅ mirror complete — $MIRROR_REPO now holds everything the template needs."
    else
        log "⚠️  finished with ${#FAILED[@]} problem(s):"
        printf '   ❌ %s\n' "${FAILED[@]}"
        log "Re-run this script; it resumes and retries only what is missing."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 3: Syntax-check both scripts**

```bash
bash -n mirror_minimax.sh && echo "mirror_minimax.sh: syntax ok"
bash -n provision_minimax.sh && echo "provision_minimax.sh: syntax ok"
```

Expected: both `syntax ok`.

- [ ] **Step 4: Verify the mirror manifest agrees with the provisioning manifest**

The two scripts carry the manifest independently, so they can drift. Add a guard test. Create `tests/test_mirror_minimax.sh`:

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
source tests/helpers.sh
source provision_minimax.sh
source mirror_minimax.sh

echo "-- mirror manifest agrees with provisioning manifest --"

assert_eq "same number of files" \
    "$(manifest_lines | grep -c .)" \
    "$(mirror_manifest_lines | grep -c .)"

assert_eq "same filenames" \
    "$(manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')"

assert_eq "same sizes" \
    "$(manifest_lines | awk -F'|' '{print $1 "=" $3}' | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | awk -F'|' '{print $1 "=" $2}' | sort | tr '\n' ' ')"

assert_eq "every sha256 is 64 hex characters" "0" \
    "$(mirror_manifest_lines | awk -F'|' 'length($3) != 64 || $3 !~ /^[0-9a-f]+$/' | grep -c .)"

# The workflow filenames are duplicated between the two scripts for the same
# reason the manifest is: each script is fetched standalone. This assertion is
# what keeps the duplicate honest. One of these names has already gone stale
# once, so it is not a hypothetical.
assert_eq "same workflow filenames" \
    "$(workflow_lines | sort | tr '\n' ' ')" \
    "$(mirror_workflow_lines | sort | tr '\n' ' ')"

finish
```

- [ ] **Step 5: Run the tests**

```bash
bash tests/run_tests.sh
```

Expected: both test files pass, `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add mirror_minimax.sh tests/test_mirror_minimax.sh .gitignore
git commit -m "feat: add the one-time model mirror script

Copies the 10 models into the user's private HF repo, verifying sha256
once during the copy so boots only need a size check. The write token is
used here and never stored in the RunPod template. Adds a test that the
two independent copies of the manifest cannot drift, and gitignores the
paid workflow JSONs."
```

---

### Task 5c: ControlNet data in both scripts

> Added 2026-09-21. The user wants two templates of her own — `minimax-h3` without ControlNet and `minimax-h3-controlnet` with it — driven by one script and one mirror. See spec decision 9 and the ControlNet tables in the spec's model inventory.

**Files:**
- Modify: `provision_minimax.sh` — add `model_ok`; replace `MODEL_MANIFEST` and `WORKFLOW_FILES`; add `controlnet_enabled`, `in_active_group`, `active_manifest_lines`, `active_workflow_lines`
- Modify: `mirror_minimax.sh` — replace the header comment and `MIRROR_MANIFEST`; give `copy_one` a per-file source; update `main`; remove `SOURCE_REPO`
- Modify: `tests/test_provision_minimax.sh` — replace the model-manifest block; add group-selection, workflow and `model_ok` blocks
- Modify: `tests/test_mirror_minimax.sh` — replace in full

**Interfaces:**
- Consumes: `safetensors_ok` and the `make_safetensors` fixture (Task 2).
- Produces:
  - `model_ok <file> <expected_bytes>` — exact byte size for every file, plus the header parse for `.safetensors`. **Task 8's `download_model` calls this, not `safetensors_ok`**, because three ControlNet files are `.pth`/`.onnx`/`.pt` and have no safetensors header.
  - `manifest_lines` → `filename|dest_rel|bytes|group`. `dest_rel` is relative to `COMFY_ROOT` (e.g. `models/vae`), no longer a bare `models/` subfolder, because the preprocessor files live under `custom_nodes/`.
  - `active_manifest_lines` → `filename|dest_rel|bytes` for the groups this template installs.
  - `workflow_lines` → `filename|group`; `active_workflow_lines` → `filename`.
  - `controlnet_enabled` — exit 0 when `MINIMAX_CONTROLNET` is `true`, `1` or `yes`, in any case.
  - `in_active_group` — stdin filter: keeps lines whose last field is `base`, or `controlnet` when enabled, and strips that field. Task 7 reuses it for node packs.

**Why both scripts in one task:** `tests/test_mirror_minimax.sh` asserts the two manifests list the same files at the same sizes. Changing either one alone turns the suite red — correctly — so they move together, and a reviewer could not approve one half without the other.

- [ ] **Step 1: Write the failing provisioning tests**

In `tests/test_provision_minimax.sh`, replace the whole block that starts at `echo "-- model manifest --"` and ends just before the final `finish` with:

```bash
echo "-- model manifest --"

assert_eq "manifest has 14 entries" "14" "$(manifest_lines | grep -c .)"

assert_eq "10 base entries" "10" \
    "$(manifest_lines | awk -F'|' '$4 == "base"' | grep -c .)"

assert_eq "4 controlnet entries" "4" \
    "$(manifest_lines | awk -F'|' '$4 == "controlnet"' | grep -c .)"

assert_eq "base group totals 83169189972 bytes" "83169189972" \
    "$(manifest_lines | awk -F'|' '$4 == "base" {s += $3} END {printf "%d", s}')"

assert_eq "manifest totals 89084560623 bytes" "89084560623" \
    "$(manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"

assert_eq "no duplicate filenames" "0" \
    "$(manifest_lines | cut -d'|' -f1 | sort | uniq -d | grep -c .)"

assert_eq "every line has four fields" "0" \
    "$(manifest_lines | awk -F'|' 'NF != 4' | grep -c .)"

assert_eq "every size is a positive integer" "0" \
    "$(manifest_lines | awk -F'|' '$3 !~ /^[1-9][0-9]*$/' | grep -c .)"

assert_eq "every group is base or controlnet" "0" \
    "$(manifest_lines | awk -F'|' '$4 != "base" && $4 != "controlnet"' | grep -c .)"

assert_eq "every destination is an allowed folder" "0" \
    "$(manifest_lines | awk -F'|' '
        $2 != "models/text_encoders" && $2 != "models/diffusion_models" &&
        $2 != "models/vae" && $2 != "models/checkpoints" &&
        $2 != "models/loras" && $2 != "models/vae_approx" &&
        $2 != "models/latent_upscale_models" && $2 != "models/controlnet" &&
        $2 !~ /^custom_nodes\/comfyui_controlnet_aux\/ckpts\/[^\/]+\/[^\/]+$/' | grep -c .)"

assert_eq "base files never leave models/" "0" \
    "$(manifest_lines | awk -F'|' '$4 == "base" && $2 !~ /^models\//' | grep -c .)"

assert_eq "text encoder is present at its exact size" "27141342152" \
    "$(manifest_lines | awk -F'|' '$1 == "qwen3vl_32b_minimax_h3_int8_convrot.safetensors" {print $3}')"

assert_eq "reference-to-video model is present" "1" \
    "$(manifest_lines | grep -c '^minimax_h3_ref2va_pruned_int8_convrot\.safetensors|models/diffusion_models|')"

assert_eq "controlnet model goes where the FunControl loader looks" "models/controlnet" \
    "$(manifest_lines | awk -F'|' '$1 == "minimax_h3_fun_controlnet_union_pruned_bf16.safetensors" {print $2}')"

echo "-- group selection --"

# active_count_with <value|__unset__> <lister> — runs the lister in a
# subshell with MINIMAX_CONTROLNET set (or unset), so no assertion can leak
# the variable into the next one.
active_count_with() {
    (
        if [[ "$1" == "__unset__" ]]; then
            unset MINIMAX_CONTROLNET
        else
            export MINIMAX_CONTROLNET="$1"
        fi
        "$2" | grep -c .
    )
}

assert_eq "unset -> base only"           "10" "$(active_count_with __unset__ active_manifest_lines)"
assert_eq "false -> base only"           "10" "$(active_count_with false active_manifest_lines)"
assert_eq "empty -> base only"           "10" "$(active_count_with '' active_manifest_lines)"
assert_eq "misspelt 'ture' -> base only" "10" "$(active_count_with ture active_manifest_lines)"
assert_eq "true -> all 14"               "14" "$(active_count_with true active_manifest_lines)"
assert_eq "TRUE -> all 14"               "14" "$(active_count_with TRUE active_manifest_lines)"
assert_eq "1 -> all 14"                  "14" "$(active_count_with 1 active_manifest_lines)"
assert_eq "yes -> all 14"                "14" "$(active_count_with yes active_manifest_lines)"

assert_eq "active lines drop the group field" "0" \
    "$( (export MINIMAX_CONTROLNET=true; active_manifest_lines) | awk -F'|' 'NF != 3' | grep -c .)"

assert_eq "base template never receives a controlnet file" "0" \
    "$( (export MINIMAX_CONTROLNET=false; active_manifest_lines) \
        | grep -cE '\.(onnx|pt|pth)\||fun_controlnet|/ckpts/')"

echo "-- workflows --"

assert_eq "two workflows" "2" "$(workflow_lines | grep -c .)"

assert_eq "main workflow is base" "MINIMAX_H3_ULTRA_WORKFLOW-V3.json|base" \
    "$(workflow_lines | grep '^MINIMAX_H3_ULTRA_WORKFLOW-V3\.json|')"

assert_eq "ControlNet workflow is controlnet" \
    "MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json|controlnet" \
    "$(workflow_lines | grep '_CONTROLNET\.json|')"

assert_eq "base template gets only the main workflow" \
    "MINIMAX_H3_ULTRA_WORKFLOW-V3.json" \
    "$( (export MINIMAX_CONTROLNET=false; active_workflow_lines) )"

assert_eq "ControlNet template gets both workflows" "2" \
    "$(active_count_with true active_workflow_lines)"

echo "-- model_ok --"

make_safetensors "$TMP/ok.safetensors"
assert_ok "safetensors: valid at its size" model_ok "$TMP/ok.safetensors" 66

# Right size, but not a safetensors file. A size-only check would accept it,
# so rejecting it proves model_ok really hands .safetensors files to the
# header check instead of stopping at the size.
printf 'not a safetensors file, only text' > "$TMP/fake.safetensors"
assert_fail "safetensors: right size, no valid header" \
    model_ok "$TMP/fake.safetensors" "$(stat -c%s "$TMP/fake.safetensors")"

printf 'ONNXDATA%.0s' {1..10} > "$TMP/model.onnx"
assert_ok   "onnx: exact size is enough"      model_ok "$TMP/model.onnx" 80
assert_fail "onnx: wrong size is rejected"    model_ok "$TMP/model.onnx" 81

head -c 50 "$TMP/model.onnx" > "$TMP/cut.pt"
assert_fail "pt: truncated download rejected" model_ok "$TMP/cut.pt" 80

assert_fail "pth: missing file rejected"      model_ok "$TMP/absent.pth" 80
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: failures on the new counts and `model_ok: command not found`, `active_manifest_lines: command not found`.

- [ ] **Step 3: Implement the provisioning side**

In `provision_minimax.sh`, add immediately after `safetensors_ok`:

```bash
# model_ok <file> <expected_bytes>
#
# Not every model is safetensors: the ControlNet preprocessors ship as .pth,
# .onnx and .pt, which have no header to parse. For those the exact byte
# size — known ahead of time from the HuggingFace tree API and baked into
# MODEL_MANIFEST — is the whole check, and it still rejects every truncated
# download. .safetensors files get the stricter safetensors_ok, header
# included, so an HTML error page of the right size cannot slip through.
model_ok() {
    local file="$1" expected="$2" actual

    case "$file" in
        *.safetensors)
            safetensors_ok "$file" "$expected"
            return
            ;;
    esac

    [[ -f "$file" ]] || return 1
    actual="$(stat -c%s "$file" 2>/dev/null)" || return 1
    [[ "$actual" == "$expected" ]]
}
```

Then replace everything from the `# filename|comfyui models subdirectory|exact size in bytes` comment down to the end of `workflow_lines()` with:

```bash
# filename|destination relative to COMFY_ROOT|exact size in bytes|group
#
# Sizes read from the HuggingFace tree API (base 2026-09-08, controlnet
# 2026-09-21). They are the contract model_ok checks each download against,
# so they must never be edited by hand — regenerate them from the API if the
# mirror content ever changes.
#
# Group "base" installs on both templates; "controlnet" only when
# MINIMAX_CONTROLNET is on. The controlnet destinations were read from the
# node sources, not guessed: the FunControl loader lists folder_paths
# category "controlnet", and comfyui_controlnet_aux reuses
# ckpts/<hf_repo_id>/<file> when it is already there instead of downloading.
MODEL_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|models/text_encoders|27141342152|base
minimax_h3_fl2va_pruned_int8_convrot.safetensors|models/diffusion_models|20970379616|base
minimax_h3_ref2va_pruned_int8_convrot.safetensors|models/diffusion_models|20970379616|base
minimax_h3_t1_image_vae_step1597.safetensors|models/vae|5207808784|base
minimax_h3_video_vae_fp16.safetensors|models/vae|5207808496|base
sam3.1_multiplex_fp16.safetensors|models/checkpoints|1745546848|base
minimax_h3_latent_upscaler_3d_fp16.safetensors|models/latent_upscale_models|690592672|base
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|models/loras|620285592|base
minimax_h3_audio_vae_fp32.safetensors|models/vae|605254808|base
taeh3.safetensors|models/vae_approx|9791388|base
minimax_h3_fun_controlnet_union_pruned_bf16.safetensors|models/controlnet|4222169456|controlnet
depth_anything_v2_vitl.pth|custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Large|1341395338|controlnet
yolox_l.onnx|custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose|216746733|controlnet
dw-ll_ucoco_384_bs5.torchscript.pt|custom_nodes/comfyui_controlnet_aux/ckpts/hr16/DWPose-TorchScript-BatchSize5|135059124|controlnet
'

# filename|group
WORKFLOW_FILES='
MINIMAX_H3_ULTRA_WORKFLOW-V3.json|base
MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json|controlnet
'

manifest_lines() {
    printf '%s\n' "$MODEL_MANIFEST" | grep -vE '^[[:space:]]*(#|$)'
}

workflow_lines() {
    printf '%s\n' "$WORKFLOW_FILES" | grep -vE '^[[:space:]]*(#|$)'
}

# controlnet_enabled — true when MINIMAX_CONTROLNET is true, 1 or yes, in any
# case. Everything else, unset or misspelt included, means base only: when
# in doubt the script installs the smaller set, never the larger one.
controlnet_enabled() {
    case "${MINIMAX_CONTROLNET:-}" in
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# in_active_group — filter for group-tagged lines on stdin, the group being
# the last |-separated field. Prints only the lines this template installs,
# with the group field removed, so every consumer sees one fixed shape
# whatever the tagging. Used for models, workflows and node packs alike.
# Plain sub() rather than NF surgery, so it behaves the same in gawk and
# mawk.
in_active_group() {
    local cn=0
    controlnet_enabled && cn=1
    awk -v cn="$cn" '
        {
            group = $0
            sub(/.*\|/, "", group)
            if (group == "base" || (cn == 1 && group == "controlnet")) {
                sub(/\|[^|]*$/, "")
                print
            }
        }'
}

active_manifest_lines() { manifest_lines | in_active_group; }
active_workflow_lines() { workflow_lines | in_active_group; }
```

- [ ] **Step 4: Run the provisioning tests**

```bash
bash tests/test_provision_minimax.sh
```

Expected: `67 test(s), 0 failure(s)`. (`tests/test_mirror_minimax.sh` is still red at this point — its manifest has 10 rows against 14. That is the drift test doing its job; Step 5 fixes it.)

- [ ] **Step 5: Mirror side — tests, then implementation**

Replace `tests/test_mirror_minimax.sh` in full with:

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
source tests/helpers.sh
source provision_minimax.sh
source mirror_minimax.sh

echo "-- mirror manifest agrees with provisioning manifest --"

assert_eq "same number of files" \
    "$(manifest_lines | grep -c .)" \
    "$(mirror_manifest_lines | grep -c .)"

assert_eq "same filenames" \
    "$(manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | cut -d'|' -f1 | sort | tr '\n' ' ')"

assert_eq "same sizes" \
    "$(manifest_lines | awk -F'|' '{print $1 "=" $3}' | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | awk -F'|' '{print $1 "=" $2}' | sort | tr '\n' ' ')"

assert_eq "every sha256 is 64 hex characters" "0" \
    "$(mirror_manifest_lines | awk -F'|' 'length($3) != 64 || $3 !~ /^[0-9a-f]+$/' | grep -c .)"

echo "-- mirror sources --"

assert_eq "every mirror line has five fields" "0" \
    "$(mirror_manifest_lines | awk -F'|' 'NF != 5' | grep -c .)"

assert_eq "every source repo is owner/name" "0" \
    "$(mirror_manifest_lines | awk -F'|' '$4 !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/' | grep -c .)"

assert_eq "every source path ends in its own filename" "0" \
    "$(mirror_manifest_lines | awk -F'|' '{n = split($5, p, "/"); if (p[n] != $1) print}' | grep -c .)"

# The base group is exactly the set that comes from the creator's repo; the
# ControlNet files all come from elsewhere. A row filed under the wrong
# source would still download fine from some public repo and never be
# noticed, so the two sets are pinned against each other.
assert_eq "base files are exactly those sourced from Aitrepreneur/FLX" \
    "$(manifest_lines | awk -F'|' '$4 == "base" {print $1}' | sort | tr '\n' ' ')" \
    "$(mirror_manifest_lines | awk -F'|' '$4 == "Aitrepreneur/FLX" {print $1}' | sort | tr '\n' ' ')"

echo "-- workflows --"

# The workflow filenames are duplicated between the two scripts for the same
# reason the manifest is: each script is fetched standalone. This assertion is
# what keeps the duplicate honest. One of these names has already gone stale
# once, so it is not a hypothetical. provision_minimax.sh tags each name with
# its group while the mirror carries every workflow, so only names compare.
assert_eq "same workflow filenames" \
    "$(workflow_lines | cut -d'|' -f1 | sort | tr '\n' ' ')" \
    "$(mirror_workflow_lines | sort | tr '\n' ' ')"

finish
```

Now change `mirror_minimax.sh` in four places.

(a) Replace the header comment's second paragraph — the lines from `# RUN THIS ONCE, EVER` through `# the two workflow JSONs if they are present locally.` — with:

```bash
# RUN THIS ONCE, EVER, from a RunPod pod (a cheap CPU-only pod is fine).
# It copies all 14 model files — the base set both templates use plus the
# ControlNet set — from their five public source repos into the user's own
# private HuggingFace repo, verifying sha256 on the way, and uploads the two
# workflow JSONs if they are present locally.
```

(b) Delete the line `SOURCE_REPO="${MINIMAX_SOURCE_REPO:-Aitrepreneur/FLX}"`. Every file now names its own source.

(c) Replace the `# filename|expected bytes|sha256` comment and the whole `MIRROR_MANIFEST` constant with:

```bash
# filename|expected bytes|sha256|source repo|path within the source repo
#
# Every file names its own source, because they come from five different
# repositories: the creator's for the base models, and four upstream
# projects for ControlNet. The mirror itself is flat — each file lands at the
# repo root under its own name, unique across all fourteen — so the
# provisioning script never needs to know where a file originally came from.
MIRROR_MANIFEST='
qwen3vl_32b_minimax_h3_int8_convrot.safetensors|27141342152|bc2ced0fbea64757fa9acddccfc0b3f4819d1dcf1da6c124d690d368be283923|Aitrepreneur/FLX|qwen3vl_32b_minimax_h3_int8_convrot.safetensors
minimax_h3_fl2va_pruned_int8_convrot.safetensors|20970379616|e889202c41dafb67b10d67b97f0d8541508036a6090af23425a5c2615d03c47a|Aitrepreneur/FLX|minimax_h3_fl2va_pruned_int8_convrot.safetensors
minimax_h3_ref2va_pruned_int8_convrot.safetensors|20970379616|9255f52b6677845ad238f20dfaafa94727053694127ab7f255c048f0f9365779|Aitrepreneur/FLX|minimax_h3_ref2va_pruned_int8_convrot.safetensors
minimax_h3_t1_image_vae_step1597.safetensors|5207808784|6c3d0bfa055986a803a566a862fcde283a1e63db62829e5ef4a2a5aebf50bb86|Aitrepreneur/FLX|minimax_h3_t1_image_vae_step1597.safetensors
minimax_h3_video_vae_fp16.safetensors|5207808496|7c1f131492e7eddacaac9069a61b81bdd39de5cc96561e677c5eab1cdce5e522|Aitrepreneur/FLX|minimax_h3_video_vae_fp16.safetensors
sam3.1_multiplex_fp16.safetensors|1745546848|9ba99c92703c2e8b4f47de2d34a539bb8e18923049e238b780d70dbe6368eb03|Aitrepreneur/FLX|sam3.1_multiplex_fp16.safetensors
minimax_h3_latent_upscaler_3d_fp16.safetensors|690592672|043e5a48e161610ef6c3ea974645220354d06fa618abca15f76d084812eb55c2|Aitrepreneur/FLX|minimax_h3_latent_upscaler_3d_fp16.safetensors
minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors|620285592|7098acf3ee75028fd9fcd948f50fcc8d995057fabb76f86bd3ca2c0ffc58e409|Aitrepreneur/FLX|minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors
minimax_h3_audio_vae_fp32.safetensors|605254808|8e505d95dd1561d47abd43d4238fd40d9bb1ae9e147ed0a4cba778d76ae4db48|Aitrepreneur/FLX|minimax_h3_audio_vae_fp32.safetensors
taeh3.safetensors|9791388|f0f60fa072089997f817402098c2fd90777cb2660dd79cf5df42fc1e3e08e527|Aitrepreneur/FLX|taeh3.safetensors
minimax_h3_fun_controlnet_union_pruned_bf16.safetensors|4222169456|57fe1e64928a63a55e3cd4586b55cd5d0eb4980648b6f31e5d9dac16fe7f1c48|Comfy-Org/MiniMax-H3|model_patches/minimax_h3_fun_controlnet_union_pruned_bf16.safetensors
depth_anything_v2_vitl.pth|1341395338|a7ea19fa0ed99244e67b624c72b8580b7e9553043245905be58796a608eb9345|depth-anything/Depth-Anything-V2-Large|depth_anything_v2_vitl.pth
yolox_l.onnx|216746733|7860ae79de6c89a3c1eb72ae9a2756c0ccfbe04b7791bb5880afabd97855a411|yzd-v/DWPose|yolox_l.onnx
dw-ll_ucoco_384_bs5.torchscript.pt|135059124|d86a0b2b59fddc0901a7076e9f59c9f8602602133ed72511c693fd11eea23d91|hr16/DWPose-TorchScript-BatchSize5|dw-ll_ucoco_384_bs5.torchscript.pt
'
```

(d) In `copy_one`: change the first two `local` lines to

```bash
    local name="$1" bytes="$2" want_sha="$3" src_repo="$4" src_path="$5"
    local local_file="$WORK/$src_path"
```

change the download log line to

```bash
    log " • downloading $name ($bytes bytes) from $src_repo"
```

and change the download call to

```bash
    if ! hf download "$src_repo" "$src_path" --local-dir "$WORK" >/dev/null; then
```

`hf download --local-dir` keeps the file's path inside the source repo, so the ControlNet model lands at `$WORK/model_patches/<file>` — which is exactly what `local_file` now points at. Everything after the download (size check, sha256, upload to `"$name"` at the mirror root, cleanup on every failure path) stays as it is.

In `main`: extend the `local` line to `local name bytes sha src_repo src_path`; replace the banner line with

```bash
    log "════ mirroring $(mirror_manifest_lines | grep -c .) files -> $MIRROR_REPO ════"
```

replace the read loop with

```bash
    while IFS='|' read -r name bytes sha src_repo src_path; do
        [[ -n "$name" ]] || continue
        copy_one "$name" "$bytes" "$sha" "$src_repo" "$src_path"
    done <<< "$(mirror_manifest_lines)"
```

and change the success line to

```bash
        log "✅ mirror complete — $MIRROR_REPO now holds everything both templates need."
```

- [ ] **Step 6: Run everything**

```bash
bash -n provision_minimax.sh && bash -n mirror_minimax.sh && echo "syntax ok"
bash tests/run_tests.sh
grep -n 'SOURCE_REPO' mirror_minimax.sh || echo "ok: no SOURCE_REPO left"
```

Expected: `syntax ok`; `9 test(s), 0 failure(s)` for the mirror file and `67 test(s), 0 failure(s)` for the provisioning file; `ALL TESTS PASSED`; `ok: no SOURCE_REPO left`.

- [ ] **Step 7: Commit**

```bash
git add provision_minimax.sh mirror_minimax.sh tests/test_provision_minimax.sh tests/test_mirror_minimax.sh
git commit -m "feat: add the ControlNet group to both manifests

Every model and workflow now carries a base/controlnet tag, and
MINIMAX_CONTROLNET picks which groups a template installs. One script
serves both the minimax-h3 and minimax-h3-controlnet templates.

Four ControlNet files join the mirror from four non-creator repos, so
each mirror row now names its own source. Three of them are not
safetensors; model_ok validates those by exact size and keeps the
header parse for .safetensors."
```

---

### Task 5d: Pin the two ControlNet packs

> Added 2026-09-21 alongside Task 5c. **Blocked until the user has forked `wyzborrero/ComfyUI-H3-FunControl` to `adri738`.**

**Files:**
- Modify: `docs/minimax-node-pins.txt` — rewrite the header comment, add a fourth field `group` to every pin, append two pins
- Modify: `tests/test_provision_minimax.sh` — add a `-- node pins --` block before `finish`

**Interfaces:**
- Consumes: `manifest_lines` (Task 5c), for the cross-check below.
- Produces: `docs/minimax-node-pins.txt` with 15 pins of `directory|clone_url|commit_sha|group`. Task 7 embeds this file verbatim and filters it through `in_active_group`.

**The 13 existing pins must not move.** They were verified live and reviewed in Task 1. Re-running Task 1's generator would silently re-resolve all 13 to whatever each upstream's HEAD is today — an unreviewed change to every pack at once. So this task tags the existing lines, appends two, and never re-resolves the old ones.

**Never probe the fork with plain `git`.** When a repo is missing, Git Credential Manager on the user's Windows desktop pops up a GitHub account picker — this happened once already. Check existence through the REST API, and when calling `git ls-remote` at all, disable both the prompt and the credential helper as shown.

- [ ] **Step 1: Confirm the fork exists**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://api.github.com/repos/adri738/ComfyUI-H3-FunControl
```

Expected: `200`. On `404`, stop and report BLOCKED — the user has not forked yet. Do not substitute the upstream URL.

- [ ] **Step 2: Write the failing tests**

Append to `tests/test_provision_minimax.sh`, immediately before the final `finish`:

```bash
echo "-- node pins --"

pins() { grep -vE '^[[:space:]]*(#|$)' docs/minimax-node-pins.txt; }

assert_eq "15 pinned packs" "15" "$(pins | grep -c .)"

assert_eq "every pin has four fields" "0" \
    "$(pins | awk -F'|' 'NF != 4' | grep -c .)"

assert_eq "13 base packs" "13" "$(pins | awk -F'|' '$4 == "base"' | grep -c .)"

assert_eq "2 controlnet packs" "2" "$(pins | awk -F'|' '$4 == "controlnet"' | grep -c .)"

assert_eq "ten packs are adri738 forks" "10" \
    "$(pins | grep -c '|https://github.com/adri738/')"

assert_eq "FunControl is the user's fork" \
    "ComfyUI-H3-FunControl|https://github.com/adri738/ComfyUI-H3-FunControl.git" \
    "$(pins | awk -F'|' '$1 == "ComfyUI-H3-FunControl" {print $1 "|" $2}')"

assert_eq "controlnet_aux stays on upstream" \
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git" \
    "$(pins | awk -F'|' '$1 == "comfyui_controlnet_aux" {print $2}')"

# The preprocessor models are placed inside a node pack's own directory. If
# that directory name and the pack's pinned directory ever disagree, the
# files land where nothing looks for them and controlnet_aux quietly
# downloads its own copies instead — every single session.
assert_eq "every custom_nodes destination is a pinned controlnet pack" "0" \
    "$(manifest_lines | awk -F'|' '$2 ~ /^custom_nodes\// {split($2, p, "/"); print p[2]}' \
        | sort -u \
        | while read -r d; do
              [ "$(pins | awk -F'|' -v d="$d" '$1 == d {print $4}')" = controlnet ] || echo "$d"
          done | grep -c .)"
```

- [ ] **Step 3: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: failures on the pin counts, the field count and both new packs.

- [ ] **Step 4: Tag, then append**

```bash
P=docs/minimax-node-pins.txt

# Header: four fields now, and the old "Regenerate to update pins" advice is
# exactly what must not happen. Plain ASCII hyphen — this line is embedded
# verbatim into provision_minimax.sh.
sed -i "1s/.*/# dir|clone_url|commit|group - base pins 2026-09-08, controlnet pins $(date +%F). Change one pin at a time, deliberately; never regenerate the whole file./" "$P"

# Tag the 13 existing pins as base. Only data lines start with a letter.
sed -i -E '/^[A-Za-z]/ s/$/|base/' "$P"

fc_sha="$(GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote https://github.com/adri738/ComfyUI-H3-FunControl.git HEAD | awk '{print $1}')"
aux_sha="$(GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote https://github.com/Fannovel16/comfyui_controlnet_aux.git HEAD | awk '{print $1}')"
echo "fc=$fc_sha"
echo "aux=$aux_sha"
```

Both must print a 40-character hex sha. If either is empty, stop — do not append a line with an empty commit. Then:

```bash
printf '%s\n' \
    "ComfyUI-H3-FunControl|https://github.com/adri738/ComfyUI-H3-FunControl.git|${fc_sha}|controlnet" \
    "comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git|${aux_sha}|controlnet" \
    >> "$P"
cat "$P"
```

The directory name `comfyui_controlnet_aux` is load-bearing: the manifest places three preprocessor files under `custom_nodes/comfyui_controlnet_aux/ckpts/`. The last assertion in Step 2 holds the two in step.

- [ ] **Step 5: Prove the 13 original pins did not move**

```bash
diff <(git show HEAD:docs/minimax-node-pins.txt | grep -vE '^#' | cut -d'|' -f1-3) \
     <(grep -vE '^#' docs/minimax-node-pins.txt | grep '|base$' | cut -d'|' -f1-3) \
  && echo "ok: the 13 original pins are untouched"
```

Expected: `ok: the 13 original pins are untouched`.

- [ ] **Step 6: Confirm both new pins are fetchable**

```bash
grep '|controlnet$' docs/minimax-node-pins.txt | while IFS='|' read -r dir url sha group; do
    if GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$url" | grep -q "^${sha}"; then
        echo "ok   $dir"
    else
        echo "FAIL $dir ($sha not on $url)"
    fi
done
```

Expected: two `ok` lines.

- [ ] **Step 7: Run everything**

```bash
bash tests/run_tests.sh
```

Expected: `75 test(s), 0 failure(s)` for the provisioning file, `9 test(s), 0 failure(s)` for the mirror file, `ALL TESTS PASSED`.

- [ ] **Step 8: Commit**

```bash
git add docs/minimax-node-pins.txt tests/test_provision_minimax.sh
git commit -m "feat: pin the two ControlNet node packs

FunControl points at the user's fork, the tenth; controlnet_aux stays
on upstream, pinned. Every pin now carries a base/controlnet group.
The 13 existing pins are tagged, not re-resolved, so none of them moved.

A test ties the preprocessor destinations in the model manifest to the
controlnet_aux directory name here: if the two ever disagree, the files
land where nothing looks and the pack silently re-downloads them."
```

---

### Task 5e: Make Ctrl+C stop the mirror

> Added 2026-09-21 after the first mirror run. The user pressed Ctrl+C and the script kept going: `hf` is a Python program, it catches SIGINT and exits with an ordinary error status, so bash sees one failed file rather than an interrupt, and — with no `set -e`, by design — moves on to the next 20 GB download. The only way out was killing processes from a second terminal.

**Files:**
- Modify: `mirror_minimax.sh` — one `trap` line at the top of `main`
- Modify: `tests/test_mirror_minimax.sh` — add an `-- interrupt --` block before `finish`

**Interfaces:**
- Consumes: `main`, `copy_one`, `upload_workflows`, `require_tools` (Task 5, 5c) — stubbed in the test.
- Produces: `main` exits 130 on INT or TERM, after the current step, without starting another file. Task 8 gives `provision_minimax.sh`'s `main` the same trap.

Why a trap works where the default does not: bash only aborts a script on Ctrl+C by default when the foreground child *died from* SIGINT. `hf` does not die from it — it handles it and returns. With a trap installed, bash runs the handler once the current child returns, whatever that child did with the signal.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_mirror_minimax.sh`, immediately before `finish`:

```bash
echo "-- interrupt --"

# What this fix is really about is INT: hf catches Ctrl+C and returns
# normally, so without a trap bash never stops. That exact situation cannot
# be replayed here — bash starts background jobs with SIGINT ignored, and a
# signal ignored on entry cannot be trapped. So INT coverage is pinned by
# reading the trap's signal list, and the stopping behaviour is proven with
# TERM, which the same trap handles identically.
assert_eq "main traps both INT and TERM" "1" \
    "$(sed -n '/^main() {/,/^}/p' mirror_minimax.sh | grep -cE '^[[:space:]]*trap .* INT TERM$')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
calls="$TMP/calls.log"
: > "$calls"

(
    require_tools()    { return 0; }
    hf()               { return 0; }
    copy_one()         { echo "copy $1" >> "$calls"; sleep 2; }
    upload_workflows() { echo "workflows" >> "$calls"; }
    export HF_WRITE_TOKEN=test-only
    WORK="$TMP/work"
    main
) > "$TMP/out.log" 2>&1 &
run_pid=$!

# Wait until the first file is being copied, so the signal lands mid-run
# rather than racing process start-up, which is slow on Windows.
for _ in $(seq 1 100); do
    grep -q '^copy ' "$calls" && break
    sleep 0.1
done
kill -TERM "$run_pid"
wait "$run_pid"
run_status=$?

# 130 comes only from the trap. Without it, TERM's default action kills the
# shell outright and the status is 143 — which is also why the two counts
# below pass either way: they guard against a trap that forgets to exit.
assert_eq "interrupted run exits 130, via the trap" "130" "$run_status"

assert_eq "no further file starts after the interrupt" "1" \
    "$(grep -c '^copy ' "$calls")"

assert_eq "workflows are not uploaded after the interrupt" "0" \
    "$(grep -c '^workflows' "$calls")"

assert_eq "the stop is announced" "1" \
    "$(grep -c 'interrupted' "$TMP/out.log")"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_mirror_minimax.sh
```

Expected: exactly three of the five new assertions fail — `main traps both INT and TERM` (0), `interrupted run exits 130, via the trap` (143: killed by TERM's default action) and `the stop is announced` (0). The two counts pass before the fix, as their comment explains; do not "fix" the test to make them fail.

- [ ] **Step 3: Add the trap**

In `mirror_minimax.sh`, make this the first statement inside `main`, before the `HF_WRITE_TOKEN` check:

```bash
    # hf is a Python program: it catches Ctrl+C and exits with an ordinary
    # error status, so bash would record one failed file and carry on to the
    # next 20 GB download. With a trap, INT (Ctrl+C) and TERM (pkill, pod
    # shutdown) stop the whole run once the current step returns. A re-run
    # resumes: files already mirrored at the right size are skipped.
    trap 'log ""; log "interrupted — stopping. Run the script again to resume."; exit 130' INT TERM
```

- [ ] **Step 4: Run everything**

```bash
bash -n mirror_minimax.sh && echo "syntax ok"
bash tests/run_tests.sh
```

Expected: `syntax ok`; `14 test(s), 0 failure(s)` for the mirror file, `75 test(s), 0 failure(s)` for the provisioning file, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add mirror_minimax.sh tests/test_mirror_minimax.sh
git commit -m "fix: stop the mirror on Ctrl+C instead of moving to the next file

hf catches SIGINT and exits normally, so bash treated each Ctrl+C as one
failed file and started the next 20 GB download. A trap on INT and TERM
now ends the run after the current step."
```

---

### Task 5f: Point both scripts at the dedicated mirror account

> Added 2026-09-21. The mirror lives on a dedicated HuggingFace account, `adri73782` — see spec decision 1. Both scripts still default to `adri738/minimax-h3-ultra-v3`, a name taken from the user's GitHub account on the assumption that her HuggingFace name matched; it does not, and no HF user `adri738` exists. Templates set `MINIMAX_HF_REPO` explicitly, so this only bites a run that omits it — such as the manual fallback — but that is exactly the run where nobody is watching.

**Files:**
- Modify: `provision_minimax.sh` — the `MIRROR_REPO` default
- Modify: `mirror_minimax.sh` — the `MIRROR_REPO` default
- Modify: `tests/test_mirror_minimax.sh` — add a `-- default mirror repo --` block before `finish`

**Interfaces:**
- Produces: `MIRROR_REPO` defaulting to `adri73782/minimax-h3-ultra-v3` in both scripts, pinned by a test.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_mirror_minimax.sh`, immediately before `finish`:

```bash
echo "-- default mirror repo --"

# The mirror lives on a dedicated HuggingFace account, adri73782 — not the
# GitHub name adri738 the first draft assumed. Each script carries the
# default on its own, since each is fetched standalone, so both are pinned
# here to the same value. Sourced in a subshell with MINIMAX_HF_REPO unset
# so that the default, not an inherited override, is what gets read.
default_repo_of() { ( unset MINIMAX_HF_REPO; source "$1"; printf '%s' "$MIRROR_REPO" ); }

assert_eq "provisioning defaults to the dedicated mirror account" \
    "adri73782/minimax-h3-ultra-v3" "$(default_repo_of provision_minimax.sh)"

assert_eq "mirror defaults to the dedicated mirror account" \
    "adri73782/minimax-h3-ultra-v3" "$(default_repo_of mirror_minimax.sh)"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_mirror_minimax.sh
```

Expected: both new assertions fail, each reporting `actual: [adri738/minimax-h3-ultra-v3]`.

- [ ] **Step 3: Change the two defaults**

```bash
sed -i 's#adri738/minimax-h3-ultra-v3#adri73782/minimax-h3-ultra-v3#' provision_minimax.sh mirror_minimax.sh
grep -n 'MIRROR_REPO=' provision_minimax.sh mirror_minimax.sh
grep -rn 'adri738/minimax' provision_minimax.sh mirror_minimax.sh tests/ || echo "ok: no stale repo id left"
```

The pattern includes the repo name on purpose: it must not touch `github.com/adri738/...` URLs, which are correct — GitHub is where the user *is* `adri738`.

- [ ] **Step 4: Run everything**

```bash
bash tests/run_tests.sh
```

Expected: `16 test(s), 0 failure(s)` for the mirror file, `75 test(s), 0 failure(s)` for the provisioning file, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add provision_minimax.sh mirror_minimax.sh tests/test_mirror_minimax.sh
git commit -m "fix: default both scripts to the adri73782 mirror account

The mirror moved to a dedicated HuggingFace account after the user's
main account ran out of private storage. Its name is adri73782; the
old default, adri738, was her GitHub name and exists nowhere on
HuggingFace. A test now pins both scripts to the same default."
```

---

### Task 6: Pod session #1 — reconnaissance and mirror

**Files:**
- Modify: `docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md` (record the answers in "Open questions")
- Modify: `provision_minimax.sh` only if reconnaissance contradicts an assumption

**Interfaces:**
- Produces: answers to the three open questions, and a populated mirror. Task 7's phase 1 branches on the `nvcc` answer; the Container Start Command in Task 9 depends on the entrypoint answer.

This is the first of two paid pod sessions. Both jobs are done in one session on purpose — reconnaissance takes 5 minutes, the mirror 20-30.

- [ ] **Step 1: Deploy a reconnaissance pod**

RunPod console → Pods → Deploy. **Set Additional Filters → CUDA Versions → 13.0 first**, then pick the **cheapest GPU** offered. (Amended 2026-09-21: an earlier draft said CPU-only. It is unverified that this image fully initialises ComfyUI under `/workspace/runpod-slim` without a GPU, and the reconnaissance is worthless if it does not. A CUDA 13 image also needs a host whose driver supports CUDA 13, which is what the filter guarantees — the same filter the user already applies for the creator's template. The cheapest such GPU costs cents more per hour than a CPU pod.) Set:

- Container Image: `runpod/comfyui:1.4.7-cuda13.0`
- Container Disk: 25 GB
- Volume Disk: 60 GB, mount `/workspace`
- Expose HTTP Ports: `8888`
- **No Container Start Command** — leave it at the image default for this session.

Connect → JupyterLab on port 8888 → Terminal.

- [ ] **Step 2: Answer the three open questions**

```bash
echo "=== Q1: is there a CUDA compiler? ==="
command -v nvcc && nvcc --version || echo "NO NVCC"

echo
echo "=== Q2: what is the image entrypoint? ==="
ls -la /start.sh 2>/dev/null || echo "NO /start.sh"
cat /proc/1/cmdline | tr '\0' ' '; echo

echo
echo "=== Q3: where do the SAM3 nodes come from? ==="
# Scoped to the ComfyUI tree: grepping / walks /proc and every mount and
# can take many minutes. The result is captured first because `head`
# always succeeds, so a bare `|| echo` after it would never fire.
r="$(grep -rl "SAM3_VideoTrack" /workspace/runpod-slim --include="*.py" 2>/dev/null | head -5)"
echo "${r:-NOT FOUND ANYWHERE}"

echo
echo "=== supporting facts ==="
ls -d /workspace/runpod-slim/ComfyUI 2>/dev/null || echo "ComfyUI not at the expected path"
ls /workspace/runpod-slim/ 2>/dev/null
for p in /workspace/runpod-slim/ComfyUI/venv/bin/python \
         /workspace/runpod-slim/ComfyUI/.venv/bin/python \
         /workspace/runpod-slim/venv/bin/python; do
  [ -x "$p" ] && echo "python: $p"
done
command -v hf aria2c curl wget
```

Record every answer. Three consequences:

- **`NO NVCC`** → Task 7 phase 1 keeps only the v1 path; delete the background-build branch rather than shipping dead code.
- **`NO /start.sh`** → the Container Start Command in Task 9 must `exec` whatever `/proc/1/cmdline` reported instead.
- **`NOT FOUND ANYWHERE`** for SAM3 → the inpainting half of the workflow needs a 16th node pack that the creator's installer does not clone. Note it, finish the rest of the plan, and resolve it in Task 10 by loading the workflow and reading which node types ComfyUI reports as missing.

- [ ] **Step 3: Run the mirror**

At this point `mirror_minimax.sh` exists only on the local branch, which has not been pushed —
there is nothing to `curl` yet. Get it onto the pod the same way you already move the
creator's installer: drag `mirror_minimax.sh` from the repo folder on your PC into
JupyterLab's `/workspace` panel.

(If the branch has been pushed to GitHub by then, `curl -fsSL
https://raw.githubusercontent.com/adri738/vace-runpod/minimax-h3-template/mirror_minimax.sh -o
mirror_minimax.sh` works instead. Either route is fine.)

Then, in the pod terminal. First, keep HuggingFace's caches on the 60 GB volume rather than the 25 GB container disk — the Xet backend keeps a chunk cache of up to ~10 GB, and the largest file is 27 GB — and make sure the `hf` CLI exists, installing it into ComfyUI's own venv if the image lacks it:

```bash
cd /workspace
export HF_HOME=/workspace/.cache/huggingface
export HF_XET_CACHE=/workspace/.cache/huggingface/xet
if ! command -v hf >/dev/null 2>&1; then
    PY="$(ls /workspace/runpod-slim/ComfyUI/.venv*/bin/python /workspace/runpod-slim/ComfyUI/venv/bin/python 2>/dev/null | head -1)"
    "$PY" -m pip install -q -U huggingface_hub
    export PATH="$(dirname "$PY"):$PATH"
fi
command -v hf && echo "hf ready"
```

Then, in the same terminal:

```bash
export HF_WRITE_TOKEN=hf_xxxxxxxx   # paste a WRITE token from huggingface.co/settings/tokens
bash /workspace/mirror_minimax.sh
```

(`mirror_minimax.sh` does not set `HF_HOME` itself yet; Task 8 adds that to both scripts. Until then the export above is load-bearing.)

Expected final line: `✅ mirror complete`. If any file fails, re-run — it resumes.

The two workflow JSONs are not on the pod, so they will be reported as skipped. That is expected; Step 4 handles them.

- [ ] **Step 4: Upload the two workflow JSONs**

Drag both files from the PC into JupyterLab's `/workspace` folder, then:

```bash
cd /workspace
bash mirror_minimax.sh
```

The models are already mirrored and get skipped in seconds; only the JSONs upload. Expected: two `✓ ... uploaded` lines.

- [ ] **Step 5: Confirm the mirror holds all 16 files**

```bash
curl -s -H "Authorization: Bearer ${HF_WRITE_TOKEN}" \
  "https://huggingface.co/api/models/adri73782/minimax-h3-ultra-v3/tree/main?recursive=1" \
  | grep -oE '"path": "[^"]*"' | sort
```

Expected: 17 paths, all at the repo root — 11 `.safetensors`, one each of `.pth`, `.onnx` and `.torchscript.pt`, the 2 `.json` workflows, and the `.gitattributes` HuggingFace creates in every new repo. The mirror is flat, so there must be no `model_patches/` prefix even though that is where the ControlNet model lives in its source repo.

- [ ] **Step 6: Create the read-only token for the template**

At https://huggingface.co/settings/tokens create a **fine-grained** token with:
- Repository access: **only** `adri73782/minimax-h3-ultra-v3`
- Permissions: **read only**

Save it — Task 9's template configuration needs it. Do not reuse the write token.

- [ ] **Step 7: Terminate the pod, then record the findings**

Terminate the pod in the RunPod console (the mirror lives on HuggingFace now; nothing on the pod is needed).

Replace the "Open questions to resolve during implementation" section of the spec with the answers, then:

```bash
git add docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md
git commit -m "docs: record reconnaissance answers from pod session 1

Resolves nvcc availability, the image entrypoint, and the origin of the
SAM3 nodes. Mirror is populated with all 14 model files and both workflows."
```

---

### Task 7: Provisioning phases 0-2 — wait, SageAttention, node packs

**Files:**
- Modify: `provision_minimax.sh`
- Modify: `tests/test_provision_minimax.sh`

**Interfaces:**
- Consumes: `sanitize_requirements` (Task 3), `in_active_group` and the `active_count_with` test helper (Task 5c), `docs/minimax-node-pins.txt` with its `group` field (Tasks 1 and 5d), the `nvcc` answer (Task 6).
- Produces: `find_comfy_python` (echoes a python path), `NODE_PACKS` (newline string of `dir|url|sha|group`), `node_pack_lines` (all 15 pins, four fields), `active_node_pack_lines` (`dir|url|sha` for the packs this template installs), `phase0_wait_for_comfyui`, `phase1_sageattention`, `phase2_node_packs`. `NODES_CHANGED` is set to `1` when phase 2 modified anything; Task 8's phase 5 reads it to decide whether ComfyUI needs restarting.

**Depends on Task 5d having landed** — the embedded-pins assertion compares against a 15-line, four-field `docs/minimax-node-pins.txt`.

**Forward dependency, on purpose:** `phase1_sageattention` calls `fetch_mirror_file`, which Task 8 defines. Bash resolves function names at call time, so the finished script is correct — but the script is **not runnable on a pod until Task 8 lands**. Unit tests pass in the meantime because they exercise only the pure functions. Do not try to run the script end to end between these two tasks.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_provision_minimax.sh`, immediately before the final `finish` call:

```bash
echo "-- node pack manifest --"

# The pin file's own content — counts, forks, groups — is already tested by
# the "-- node pins --" block from Task 5d. What this block adds is that the
# copy embedded in the script matches it, and that the group filter selects
# the right packs for each template.

# The embedded copy must never drift from the reviewable source of truth.
assert_eq "embedded pins match docs/minimax-node-pins.txt" \
    "$(grep -vE '^[[:space:]]*(#|$)' docs/minimax-node-pins.txt | sort | tr '\n' ' ')" \
    "$(node_pack_lines | sort | tr '\n' ' ')"

assert_eq "base template installs 13 packs" "13" \
    "$(active_count_with false active_node_pack_lines)"

assert_eq "ControlNet template installs 15 packs" "15" \
    "$(active_count_with true active_node_pack_lines)"

assert_eq "active pack lines are dir|url|sha" "0" \
    "$( (export MINIMAX_CONTROLNET=true; active_node_pack_lines) \
        | awk -F'|' 'NF != 3 || $3 !~ /^[0-9a-f]+$/ || length($3) != 40' | grep -c .)"

assert_eq "base template never clones a ControlNet pack" "0" \
    "$( (export MINIMAX_CONTROLNET=false; active_node_pack_lines) \
        | grep -cE '^(ComfyUI-H3-FunControl|comfyui_controlnet_aux)\|')"

echo "-- find_comfy_python --"

# On the real image the only venv is .venv-cu128. An earlier draft searched
# venv/ and .venv/ and then fell back to the system python3, which would
# have installed every requirement into the wrong interpreter, silently.
find_in() { COMFY_ROOT="$1" COMFY_PYTHON="" find_comfy_python; }

fake="$TMP/fakecomfy"
mkdir -p "$fake/.venv-cu128/bin"
printf '#!/bin/sh\n' > "$fake/.venv-cu128/bin/python"
chmod +x "$fake/.venv-cu128/bin/python"
assert_eq "finds the image's .venv-cu128" "$fake/.venv-cu128/bin/python" "$(find_in "$fake")"

mkdir -p "$TMP/novenv"
assert_fail "no venv: fails rather than falling back to system python" find_in "$TMP/novenv"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: FAIL — `node_pack_lines: command not found` and `active_node_pack_lines: command not found`.

- [ ] **Step 3: Add the node manifest and phases 0-2**

First embed the pins. Add to `provision_minimax.sh` after `active_workflow_lines`, pasting the 15 non-comment lines of `docs/minimax-node-pins.txt` verbatim between the quotes — all four fields, group included (the test in Step 1 enforces that they match):

```bash
# Custom-node packs: directory|clone url|pinned commit|group.
#
# Kept identical to docs/minimax-node-pins.txt, which is the reviewable
# source of truth; tests/test_provision_minimax.sh fails if they drift.
# Ten of these point at forks under adri738 so a deleted upstream cannot
# break the template. Pinning protects against breaking changes; forking
# protects against deletion. Both are needed. The group field works as it
# does for models: "controlnet" packs install only when MINIMAX_CONTROLNET
# is on.
NODE_PACKS='
<paste the 15 non-comment lines of docs/minimax-node-pins.txt here>
'

node_pack_lines() {
    printf '%s\n' "$NODE_PACKS" | grep -vE '^[[:space:]]*(#|$)'
}

active_node_pack_lines() { node_pack_lines | in_active_group; }
```

Then add the phases, after `active_node_pack_lines`. Every loop over node packs below reads `active_node_pack_lines`, never `node_pack_lines` — a base-template pod must not clone the ControlNet packs.

```bash
setup_logging() {
    mkdir -p "$(dirname "$LOG")" "$STAGING"
    exec > >(tee -a "$LOG") 2>&1
}

# find_comfy_python — prints ComfyUI's own interpreter, or fails.
#
# On runpod/comfyui:1.4.7-cuda13.0 the only venv is .venv-cu128 — a legacy
# name over a CUDA 13 torch (reconnaissance, 2026-09-21). There is no venv/
# or .venv/, so those alone would miss it. And there is deliberately no
# fallback to the system python3: pip-installing node requirements and
# SageAttention into the wrong interpreter would "succeed" silently and
# leave ComfyUI without them. Failing loudly is the safer outcome.
find_comfy_python() {
    local candidate
    for candidate in \
        "${COMFY_PYTHON:-}" \
        "$COMFY_ROOT/.venv-cu130/bin/python" \
        "$COMFY_ROOT/.venv-cu128/bin/python" \
        "$COMFY_ROOT"/.venv*/bin/python \
        "$COMFY_ROOT/venv/bin/python" \
        "$COMFY_ROOT/.venv/bin/python"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

phase0_wait_for_comfyui() {
    local waited=0
    local limit="${COMFY_WAIT_SECONDS:-1800}"

    log ""
    log "──── phase 0: waiting for ComfyUI ────"

    while [[ ! -d "$COMFY_ROOT/custom_nodes" ]]; do
        if (( waited >= limit )); then
            log "❌ ComfyUI never appeared at $COMFY_ROOT after ${limit}s"
            FAILED+=("phase 0: ComfyUI not found at $COMFY_ROOT")
            return 1
        fi
        sleep 10
        waited=$(( waited + 10 ))
    done

    if ! PYTHON="$(find_comfy_python)"; then
        log "❌ no ComfyUI virtualenv under $COMFY_ROOT — refusing to fall back to the system python"
        FAILED+=("phase 0: ComfyUI python not found")
        return 1
    fi
    log "ComfyUI root : $COMFY_ROOT (ready after ${waited}s)"
    log "ComfyUI python: $PYTHON"
}

# cuda_majors_match — true when nvcc and ComfyUI's torch target the same
# CUDA major version. torch's extension builder refuses a major mismatch, so
# without this check a future image bump could burn 15-30 min of pod time on
# every boot building a wheel that can never be produced. (On 1.4.7 both are
# 13 — see the spec's reconnaissance results.)
cuda_majors_match() {
    local nv tv
    nv="$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]*\)\..*/\1/p')"
    tv="$("$PYTHON" -c 'import torch; print((torch.version.cuda or "").split(".")[0])' 2>/dev/null)"
    [[ -n "$nv" && "$nv" == "$tv" ]]
}

# Name of the prebuilt SageAttention wheel in the mirror. It encodes the
# python, CUDA and torch versions, so a wheel built on one image is never
# installed onto an incompatible one.
sage_wheel_path() {
    local py cu tv
    py="$("$PYTHON" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null)" || return 1
    tv="$("$PYTHON" -c 'import torch; print(torch.__version__.split("+")[0])' 2>/dev/null)" || return 1
    cu="$("$PYTHON" -c 'import torch; print("cu" + torch.version.cuda.replace(".", ""))' 2>/dev/null)" || return 1
    printf 'wheels/sageattention-%s-%s-torch%s.whl\n' "$py" "$cu" "$tv"
}

phase1_sageattention() {
    local wheel_path wheel_local

    log ""
    log "──── phase 1: SageAttention ────"

    if "$PYTHON" -c 'import sageattention' 2>/dev/null; then
        log "• already importable — skip"
        return 0
    fi

    wheel_path="$(sage_wheel_path)" || wheel_path=""

    if [[ -n "$wheel_path" ]]; then
        wheel_local="$STAGING/$(basename "$wheel_path")"
        log "• looking for a prebuilt wheel: $wheel_path"
        if fetch_mirror_file "$wheel_path" "$wheel_local" \
            && "$PYTHON" -m pip install --no-input "$wheel_local"; then
            log "• installed SageAttention 2++ from the mirror ✔"
            rm -f "$wheel_local"
            return 0
        fi
        rm -f "$wheel_local"
        log "• no usable prebuilt wheel for this image"
    fi

    if "$PYTHON" -m pip install --no-input sageattention; then
        log "• installed SageAttention v1 from PyPI ✔"
    else
        log "• could not install SageAttention at all"
        FAILED+=("phase 1: no SageAttention")
    fi

    if command -v nvcc >/dev/null 2>&1 && cuda_majors_match; then
        log "• nvcc matches torch's CUDA — building SageAttention 2++ in the background"
        log "  (ComfyUI stays usable on v1 while this runs)"
        nohup bash "$SCRIPT_PATH" --build-sage >> "$LOG" 2>&1 </dev/null &
    else
        log "• no nvcc, or its CUDA major differs from torch's — staying on SageAttention v1"
    fi
}

# Runs in the background, once ever. Produces a wheel the user uploads to
# the mirror by hand, so the pod never needs a write token.
build_sage_wheel() {
    local src="$STAGING/SageAttention"
    local out="/workspace/wheels"
    local wheel_path wheel

    PYTHON="$(find_comfy_python)"
    wheel_path="$(sage_wheel_path)" || return 1

    log ""
    log "──── background: building SageAttention 2++ ────"

    rm -rf "$src"
    if ! git clone --depth 1 https://github.com/thu-ml/SageAttention.git "$src"; then
        log "❌ could not clone SageAttention"
        return 1
    fi

    mkdir -p "$out"
    if ! (cd "$src" && "$PYTHON" -m pip wheel . --no-deps --wheel-dir "$out"); then
        log "❌ SageAttention build failed — staying on v1"
        return 1
    fi

    wheel="$(ls -t "$out"/sageattention-*.whl 2>/dev/null | head -1)"
    if [[ -z "$wheel" ]]; then
        log "❌ build produced no wheel"
        return 1
    fi

    "$PYTHON" -m pip install --no-input --force-reinstall "$wheel" || true

    log ""
    log "✅ SageAttention 2++ built: $wheel"
    log "   ONE-TIME MANUAL STEP — upload it so every future pod skips this build:"
    log "     export HF_WRITE_TOKEN=hf_xxx"
    log "     HF_TOKEN=\$HF_WRITE_TOKEN hf upload $MIRROR_REPO $wheel $wheel_path"
    log "   Do this before terminating the pod; the wheel dies with the volume."
}

phase2_node_packs() {
    local dir url sha target current req tmp_req

    log ""
    log "──── phase 2: custom nodes ────"

    NODES_CHANGED=0
    mkdir -p "$COMFY_ROOT/custom_nodes"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue
        target="$COMFY_ROOT/custom_nodes/$dir"

        if [[ -d "$target/.git" ]]; then
            current="$(git -C "$target" rev-parse HEAD 2>/dev/null || true)"
            if [[ "$current" == "$sha" ]]; then
                log " [SKIP] $dir already at ${sha:0:8}"
                continue
            fi
        else
            rm -rf "$target"
            if ! git clone --filter=blob:none "$url" "$target"; then
                log " ❌ clone failed: $dir"
                FAILED+=("node clone: $dir")
                continue
            fi
        fi

        git -C "$target" fetch --depth 1 origin "$sha" >/dev/null 2>&1 \
            || git -C "$target" fetch origin >/dev/null 2>&1 \
            || true

        if git -C "$target" checkout --detach "$sha" >/dev/null 2>&1; then
            log " • $dir → ${sha:0:8}"
            NODES_CHANGED=1
        else
            log " ❌ commit not found: $dir @ $sha"
            FAILED+=("node checkout: $dir")
        fi
    done <<< "$(active_node_pack_lines)"

    log ""
    log "──── phase 2b: safe node requirements ────"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue

        # The image manages these two itself; their requirements would only
        # fight with the runtime.
        if [[ "$dir" == "ComfyUI-Manager" || "$dir" == "ComfyUI-KJNodes" ]]; then
            log " [SKIP] $dir is managed by the image"
            continue
        fi

        req="$COMFY_ROOT/custom_nodes/$dir/requirements.txt"
        [[ -f "$req" ]] || { log " [SKIP] $dir has no requirements.txt"; continue; }

        tmp_req="$(mktemp)"
        sanitize_requirements "$req" "$tmp_req"

        if [[ ! -s "$tmp_req" ]]; then
            log " [SKIP] $dir needs nothing beyond the runtime"
            rm -f "$tmp_req"
            continue
        fi

        log " • installing requirements for $dir"
        if ! "$PYTHON" -m pip install --no-input --prefer-binary \
            --upgrade-strategy only-if-needed -r "$tmp_req"; then
            log " ⚠️  some optional requirements for $dir failed"
        fi
        rm -f "$tmp_req"
    done <<< "$(active_node_pack_lines)"

    # VideoHelperSuite needs this and it touches nothing GPU-related.
    "$PYTHON" -m pip install --no-input --prefer-binary imageio-ffmpeg >/dev/null 2>&1 \
        || FAILED+=("pip: imageio-ffmpeg")
}
```

Also add `SCRIPT_PATH` next to the other constants at the top of the file, so the background build can re-invoke the script by an absolute path:

```bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
```

Task 6 found `nvcc` 13.0 and torch 2.10+cu130 on the image, so the background-build branch and `build_sage_wheel` both ship. `cuda_majors_match` keeps a future image bump from wasting pod time on a build that cannot succeed.

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
bash tests/run_tests.sh
bash -n provision_minimax.sh && echo "syntax ok"
```

Expected: `ALL TESTS PASSED` and `syntax ok`. The phase functions are not unit-tested — they are network and filesystem operations against a pod, verified in Task 10.

- [ ] **Step 5: Commit**

```bash
git add provision_minimax.sh tests/test_provision_minimax.sh
git commit -m "feat: add provisioning phases 0-2

Waits for the image to place ComfyUI, installs SageAttention (mirror
wheel, else PyPI v1, with an optional background v2++ build), and clones
the active node packs (13, or 15 with ControlNet) at pinned commits
with sanitized requirements."
```

---

### Task 8: Provisioning phases 3-5 — models, workflows, restart

**Files:**
- Modify: `provision_minimax.sh`
- Modify: `mirror_minimax.sh` — only the two `HF_HOME` / `HF_XET_CACHE` exports, see Step 2b

**Interfaces:**
- Consumes: `model_ok`, `controlnet_enabled`, `active_manifest_lines` and `active_workflow_lines` (Task 5c), `active_node_pack_lines` and `NODES_CHANGED` (Task 7).
- Produces: `fetch_mirror_file <repo_path> <output_path>` — used by Task 7's phase 1 as well. `main` becomes the real entry point.

Parallel downloads report their result through marker files rather than by appending to `FAILED`, because a background subshell cannot mutate its parent's array.

- [ ] **Step 1: Add the download layer and phases 3-5**

Add to `provision_minimax.sh` after `phase2_node_packs`:

```bash
# fetch_mirror_file <path in the mirror repo> <local output path>
#
# Tries the fastest transport first and degrades gracefully. Every
# transport carries the read-only token, because the mirror is private.
fetch_mirror_file() {
    local repo_path="$1" out="$2"
    local url="https://huggingface.co/${MIRROR_REPO}/resolve/main/${repo_path}"
    local hf_dir="$STAGING/hf/$(basename "$repo_path")"

    mkdir -p "$(dirname "$out")"

    if [[ -z "${HF_TOKEN:-}" ]]; then
        log "   ✗ HF_TOKEN is not set — the mirror is private and cannot be read"
        return 1
    fi

    if command -v hf >/dev/null 2>&1; then
        rm -rf "$hf_dir"
        if HF_TOKEN="$HF_TOKEN" hf download "$MIRROR_REPO" "$repo_path" \
            --local-dir "$hf_dir" >/dev/null 2>&1 \
            && mv -f "$hf_dir/$repo_path" "$out" 2>/dev/null; then
            rm -rf "$hf_dir"
            return 0
        fi
        rm -rf "$hf_dir"
    fi

    if command -v aria2c >/dev/null 2>&1; then
        if aria2c --continue=true --max-connection-per-server=16 --split=16 \
                  --min-split-size=8M --file-allocation=none \
                  --auto-file-renaming=false --allow-overwrite=true \
                  --max-tries=5 --retry-wait=3 --console-log-level=warn \
                  --header="Authorization: Bearer ${HF_TOKEN}" \
                  --dir="$(dirname "$out")" --out="$(basename "$out")" \
                  "$url"; then
            return 0
        fi
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -L --fail --retry 5 --retry-delay 3 --retry-all-errors \
                --connect-timeout 30 -C - \
                -H "Authorization: Bearer ${HF_TOKEN}" \
                -o "$out" "$url"; then
            return 0
        fi
    fi

    command -v wget >/dev/null 2>&1 && \
        wget --continue --tries=5 --timeout=120 \
             --header="Authorization: Bearer ${HF_TOKEN}" \
             -O "$out" "$url"
}

# download_model <filename> <dest dir relative to COMFY_ROOT> <bytes> <status dir>
#
# The destination is a full relative directory, not a models/ subfolder,
# because the ControlNet preprocessors live under custom_nodes/. Validation
# goes through model_ok, which handles the .pth/.onnx/.pt files that have no
# safetensors header.
download_model() {
    local name="$1" dest_rel="$2" bytes="$3" status="$4"
    local dest="$COMFY_ROOT/$dest_rel/$name"
    local stage="$STAGING/${name}.part"

    mkdir -p "$(dirname "$dest")"

    if model_ok "$dest" "$bytes"; then
        log " [SKIP] $name (already valid)"
        : > "$status/ok.$name"
        return 0
    fi

    if [[ -e "$dest" ]]; then
        log " [WARN] discarding incomplete $name"
        rm -f "$dest"
    fi

    log " • downloading $name"
    rm -f "$stage"

    if fetch_mirror_file "$name" "$stage" && model_ok "$stage" "$bytes"; then
        mv -f "$stage" "$dest"
        log "   ✓ $name"
        : > "$status/ok.$name"
        return 0
    fi

    rm -f "$stage"
    log "   ✗ FAILED $name"
    : > "$status/fail.$name"
    return 1
}

phase3_models() {
    local status name dest_rel bytes running=0 failures count total

    log ""
    log "──── phase 3: models ────"

    # Counted from the manifest rather than hardcoded: 10 files on the base
    # template, 14 with ControlNet.
    count="$(active_manifest_lines | grep -c .)"
    total="$(active_manifest_lines | awk -F'|' '{s += $3} END {printf "%d", s}')"
    log "$count files, $total bytes, ${MODEL_PARALLEL} at a time"

    status="$STAGING/status"
    rm -rf "$status"
    mkdir -p "$status"

    # Largest first across both groups, so the 25 GB text encoder starts at
    # once instead of queueing behind small files.
    while IFS='|' read -r name dest_rel bytes; do
        [[ -n "$name" ]] || continue
        download_model "$name" "$dest_rel" "$bytes" "$status" &
        running=$(( running + 1 ))
        if (( running >= MODEL_PARALLEL )); then
            wait -n 2>/dev/null || true
            running=$(( running - 1 ))
        fi
    done <<< "$(active_manifest_lines | sort -t'|' -k3,3nr)"

    wait

    failures="$(find "$status" -name 'fail.*' | wc -l | tr -d ' ')"
    if [[ "$failures" != "0" ]]; then
        # Process substitution, not a pipe: a piped while-loop runs in a
        # subshell and its appends to FAILED would be discarded.
        while IFS= read -r entry; do
            FAILED+=("model: ${entry#fail.}")
        done < <(find "$status" -name 'fail.*' -exec basename {} \;)
    fi

    # The HF CLI keeps its own copy under the staging dir; 77-83 GB is not
    # something to store twice on a 150 GB volume.
    rm -rf "$STAGING/hf"
}

phase4_workflows() {
    local name dest_dir out

    log ""
    log "──── phase 4: workflows ────"

    dest_dir="$COMFY_ROOT/user/default/workflows"
    mkdir -p "$dest_dir"

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        out="$dest_dir/$name"

        if [[ -s "$out" ]]; then
            log " [SKIP] $name already present"
            continue
        fi

        if fetch_mirror_file "$name" "$out" && [[ -s "$out" ]]; then
            log " ✓ $name"
        else
            rm -f "$out"
            log " ❌ $name"
            FAILED+=("workflow: $name")
        fi
    done <<< "$(active_workflow_lines)"
}

phase5_restart_and_verify() {
    local pattern='[p]ython.*main\.py.*--port(=|[[:space:]])8188'
    local args_file="/workspace/runpod-slim/comfyui_args.txt"
    local log_start=1 new_log new_pid dir url sha missing=0 extra
    local -a args=(--listen 0.0.0.0 --port 8188 --enable-cors-header)

    log ""
    log "──── phase 5: restart and verify ────"

    if [[ "${NODES_CHANGED:-0}" != "1" ]] && pgrep -f "$pattern" >/dev/null 2>&1; then
        log "• no node changes and ComfyUI is running — no restart needed"
        return 0
    fi

    if [[ -f "$args_file" ]]; then
        extra="$(grep -vE '^[[:space:]]*(#|$)' "$args_file" | tr '\n' ' ' || true)"
        if [[ -n "$extra" ]]; then
            # Intentional word splitting: these are CLI flags.
            # shellcheck disable=SC2206
            local parsed=( $extra )
            args+=("${parsed[@]}")
        fi
    fi

    if pgrep -f "$pattern" >/dev/null 2>&1; then
        log "• stopping the running ComfyUI"
        pkill -f "$pattern" 2>/dev/null || true
        for _ in {1..40}; do
            pgrep -f "$pattern" >/dev/null 2>&1 || break
            sleep 0.5
        done
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            log "❌ the old ComfyUI process would not stop; not starting a second one"
            FAILED+=("phase 5: stale ComfyUI process")
            return 1
        fi
    fi

    log_start=$(( $(wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

    cd "$COMFY_ROOT" || return 1
    nohup "$PYTHON" main.py "${args[@]}" >> "$LOG" 2>&1 </dev/null &
    new_pid=$!
    log "• started ComfyUI as PID $new_pid"

    for _ in {1..180}; do
        if ! kill -0 "$new_pid" 2>/dev/null; then
            log "❌ ComfyUI exited during startup"
            FAILED+=("phase 5: ComfyUI exited")
            return 1
        fi
        new_log="$(tail -n +"$log_start" "$LOG" 2>/dev/null || true)"
        grep -Fq "Starting server" <<< "$new_log" && break
        sleep 1
    done

    new_log="$(tail -n +"$log_start" "$LOG" 2>/dev/null || true)"
    if ! grep -Fq "Starting server" <<< "$new_log"; then
        log "❌ ComfyUI did not finish starting within 180s"
        FAILED+=("phase 5: startup timeout")
        return 1
    fi

    log "• ComfyUI reached server startup; checking node packs"

    while IFS='|' read -r dir url sha; do
        [[ -n "$dir" ]] || continue
        if grep -Fq "/custom_nodes/${dir}" <<< "$new_log"; then
            log "   ✓ loaded: $dir"
        else
            log "   ✗ NOT LOADED: $dir"
            missing=$(( missing + 1 ))
        fi
    done <<< "$(active_node_pack_lines)"

    if (( missing > 0 )); then
        FAILED+=("phase 5: $missing node pack(s) did not load")
    fi
}

summary() {
    log ""
    log "──────────────────────────────────"
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        log "✅ MiniMax H3 provisioning finished — ComfyUI is ready on port 8188."
        log "   Both workflows are in ComfyUI's saved-workflow list."
    else
        log "⚠️  finished with ${#FAILED[@]} problem(s):"
        printf '   ❌ %s\n' "${FAILED[@]}"
        log "Re-run this script; it retries only what is missing:"
        log "   bash /workspace/provision_minimax.sh"
    fi
    log "════ done: $(date) ════"
}
```

- [ ] **Step 2: Replace the placeholder `main`**

Replace the `main` function created in Task 2 with:

```bash
main() {
    setup_logging

    # Keep HuggingFace's caches on the 150 GB volume, not the 25 GB container
    # disk: the Xet backend keeps a chunk cache of up to ~10 GB, and the
    # largest model is 27 GB. Exported here, inside main, so that sourcing
    # the script for tests still changes nothing.
    export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
    export HF_XET_CACHE="${HF_XET_CACHE:-$HF_HOME/xet}"

    log ""
    log "════ MiniMax H3 provisioning started (${1:-manual}): $(date) ════"

    # Say which template this pod is before doing anything, so a log read
    # after the fact shows at a glance whether ControlNet was meant to be here.
    if controlnet_enabled; then
        log "template: minimax-h3-controlnet (MINIMAX_CONTROLNET=${MINIMAX_CONTROLNET})"
    else
        log "template: minimax-h3 (MINIMAX_CONTROLNET=${MINIMAX_CONTROLNET:-unset}, base only)"
    fi

    if [[ "${1:-}" == "--build-sage" ]]; then
        build_sage_wheel
        exit 0
    fi

    phase0_wait_for_comfyui || { summary; exit 1; }
    phase1_sageattention
    phase2_node_packs
    phase3_models
    phase4_workflows
    phase5_restart_and_verify
    summary
}
```

- [ ] **Step 2b: Give the mirror script the same cache location**

`mirror_minimax.sh` has the same exposure: it downloads files of up to 27 GB, and without `HF_HOME` the Xet chunk cache lands on the 25 GB container disk. In its `main`, immediately after the `HF_WRITE_TOKEN` check, add:

```bash
    # Keep HuggingFace's caches on the /workspace volume, not the 25 GB
    # container disk: the Xet backend keeps a chunk cache of up to ~10 GB.
    export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
    export HF_XET_CACHE="${HF_XET_CACHE:-$HF_HOME/xet}"
```

Nothing else in `mirror_minimax.sh` changes. (The one-time mirror run in Task 6 exports these by hand, because it happens before this task lands.)

- [ ] **Step 3: Run the tests and syntax check**

```bash
bash tests/run_tests.sh
bash -n provision_minimax.sh && bash -n mirror_minimax.sh && echo "syntax ok"
grep -c 'HF_HOME=' provision_minimax.sh mirror_minimax.sh
```

The last line must report `1` for each file: the export lives inside `main`, once.

Expected: `ALL TESTS PASSED` and `syntax ok`.

- [ ] **Step 4: Confirm sourcing the script has no side effects**

This guards the design rule that all side effects live in functions. If it fails, some top-level code is doing work at source time.

```bash
mkdir -p /tmp/sideeffect && cd /tmp/sideeffect
before="$(ls -A | wc -l)"
( source "C:/Users/Trabajo/OneDrive/Mis_Proyectos/Proyectos_Claude/template_runpod_aitrepeneur/provision_minimax.sh" )
after="$(ls -A | wc -l)"
[ "$before" = "$after" ] && echo "ok: sourcing is inert" || echo "FAIL: sourcing created files"
cd - >/dev/null
```

Expected: `ok: sourcing is inert`.

- [ ] **Step 5: Commit**

```bash
git add provision_minimax.sh
git commit -m "feat: add provisioning phases 3-5

Downloads the active models (10, or 14 with ControlNet) from the private
mirror in parallel, largest first, with staged, validated, atomic writes;
places the active workflows in ComfyUI's saved list; restarts ComfyUI
only when nodes changed and verifies every active pack loaded before
declaring success."
```

---

### Task 9: Documentation and template configuration

**Files:**
- Create: `MINIMAX_INSTRUCTIONS.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: the entrypoint answer from Task 6 (the Container Start Command must `exec` the right thing).
- Produces: the document the user actually follows when deploying a pod.

- [ ] **Step 1: Write `MINIMAX_INSTRUCTIONS.md`**

Match the voice and structure of `SDXL_INSTRUCTIONS.md`. One document covers **both** of the user's MiniMax templates. It must contain:

1. **Which template to pick, first thing.** A short table: `minimax-h3` — the main workflow, same as the creator's, ~77 GB per session; `minimax-h3-controlnet` — the main workflow *and* the ControlNet one, ~83 GB per session. One line noting that the creator's own template remains a third option and that the user's existing `RUNBOOK_MINIMAX_RUNPOD.md` is the guide for that one (spec decision 8).
2. **Deploy steps** — RunPod console → Pods → Deploy, GPU **RTX 6000 Ada (48 GB)**, template **minimax-h3** or **minimax-h3-controlnet**, On-Demand.
3. **A prominent warning, near the top:** *this pod is always terminated, never stopped — download every generated video before terminating, from JupyterLab at `/workspace/runpod-slim/ComfyUI/output`.*
4. **First-boot timing** — roughly 15-25 minutes, dominated by the models. Progress: Connect → JupyterLab (8888) → Terminal → `tail -f /workspace/provision_minimax.log`. The log's second line names the template (`template: minimax-h3` or `template: minimax-h3-controlnet`) — if it names the wrong one, the `MINIMAX_CONTROLNET` variable on the template is wrong. Wait for `✅ MiniMax H3 provisioning finished`.
5. **Manual fallback**, if the log file never appears after ~5 minutes. First `echo $MINIMAX_CONTROLNET` to confirm the terminal sees the template's variable; if it prints nothing on the ControlNet template, prefix the command with `MINIMAX_CONTROLNET=true`:

   ```
   cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o provision_minimax.sh && bash provision_minimax.sh
   ```

6. **Using it** — Connect → HTTP Service port 8188. The workflows are already in the workflow list (sidebar → Workflows); no drag and drop needed. For *how* to use them — groups, modes, prompting, what to leave enabled — point to `RUNBOOK_MINIMAX_RUNPOD.md` sections 3-5 rather than repeating them; the workflow is identical under every template. State just the two toggles that differ because of this template: `RF PATCH SAGE` **enabled** (this script does not pass `--use-sage-attention`, so the workflow group is the only route; check with `cat /workspace/runpod-slim/comfyui_args.txt`) and `RF SPEEDUP` **bypassed**.
7. **The template settings table** exactly as in the spec, including `MINIMAX_CONTROLNET` and the Container Start Command from Step 2 below, and a sentence saying the two templates differ in that one variable and their name.
8. **The one-time SageAttention wheel upload**, quoting the command the script prints, and explaining that doing it once makes every later pod skip a 15-30 minute build.
9. **Troubleshooting**, four symptoms with fixes: red "missing node" boxes (provisioning did not finish — check the log for ❌ lines, re-run the fallback, refresh the tab); red ControlNet nodes on the ControlNet template specifically (the log's template line says `minimax-h3` — fix the variable, then re-run); a model missing from a dropdown (same fallback, it re-downloads only what is missing); `HF_TOKEN is not set` in the log (the template env var is missing or the token was revoked).
10. **How to bump the pinned image or a node commit** deliberately: edit the image version in the templates; for a node pack, change that one line in `docs/minimax-node-pins.txt` and the matching line in `NODE_PACKS`, then re-commit. **Never regenerate the pin file wholesale** — that silently moves every pack at once.

- [ ] **Step 2: Record the Container Start Command**

Use this, substituting whatever Task 6 found if the entrypoint was not `/start.sh`:

```
{"entrypoint": ["bash", "-c", "nohup bash -c 'i=0; while [ ! -d /workspace/runpod-slim/ComfyUI/custom_nodes ] && [ $i -lt 180 ]; do sleep 5; i=$((i+1)); done; curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o /workspace/provision_minimax.sh; bash /workspace/provision_minimax.sh --boot' > /workspace/provision-boot.log 2>&1 & exec /start.sh"]}
```

Note it fetches from `main`, so the branch must be merged before a pod can use it. Task 10 Step 1 handles that.

- [ ] **Step 3: Update `README.md`**

Add MiniMax H3 to the repo intro as the third template, one short paragraph pointing at `MINIMAX_INSTRUCTIONS.md`, in the same register as the existing VACE and SDXL entries.

- [ ] **Step 4: Check every command in the docs is copy-pasteable**

```bash
grep -n 'raw.githubusercontent.com' MINIMAX_INSTRUCTIONS.md
grep -n 'adri738/vace-runpod/main/' MINIMAX_INSTRUCTIONS.md
```

Expected: every URL points at `main` (not the feature branch) and at `provision_minimax.sh`.

- [ ] **Step 5: Confirm no paid content leaked into the repo**

```bash
git ls-files | grep -i 'MINIMAX.*WORKFLOW.*json' && echo "BAD: paid JSON tracked" || echo "ok: no workflow JSONs tracked"
```

Expected: `ok: no workflow JSONs tracked`.

- [ ] **Step 6: Commit**

```bash
git add MINIMAX_INSTRUCTIONS.md README.md
git commit -m "docs: add the MiniMax H3 template guide

Deploy steps, template settings, the always-terminate warning about
saving outputs first, the one-time SageAttention wheel upload, and
troubleshooting."
```

---

### Task 10: Pod session #2 — end-to-end validation

**Files:**
- Modify: whatever the run proves wrong

**Interfaces:**
- Consumes: everything. This is the only test that decides whether the template works.

- [ ] **Step 1: Merge to `main`**

The Container Start Command fetches from `main`, so nothing can be tested until the branch lands.

```bash
bash tests/run_tests.sh
git checkout main
git merge --no-ff minimax-h3-template -m "feat: MiniMax H3 Ultra V3 RunPod template"
git push origin main
curl -sI https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh | head -1
```

Expected: `ALL TESTS PASSED` first, then `HTTP/2 200` for the raw URL.

- [ ] **Step 2: Create the RunPod template**

RunPod console → Templates → New Template, **twice**. Fill both in exactly from the table in `MINIMAX_INSTRUCTIONS.md`, including the read-only `HF_TOKEN` created in Task 6 Step 6 and `MINIMAX_HF_REPO=adri73782/minimax-h3-ultra-v3`:

- `minimax-h3` with `MINIMAX_CONTROLNET=false`
- `minimax-h3-controlnet` with `MINIMAX_CONTROLNET=true`

Every other field is identical. Creating a template costs nothing; only deploying a pod does.

- [ ] **Step 3: Deploy the ControlNet template and watch the full run**

Validate `minimax-h3-controlnet`, not the base one: it is the strict superset, so one GPU session exercises every pack, model and workflow. The base template's narrower selection is already proven by the group-filter unit tests from Task 5c.

Deploy On-Demand on an RTX 6000 Ada. Then JupyterLab (8888) → Terminal:

```bash
tail -f /workspace/provision_minimax.log
```

Expected: the second line reads `template: minimax-h3-controlnet`; end state `✅ MiniMax H3 provisioning finished`, with `✓ loaded:` for all **15** packs and no `❌` lines. Note the wall-clock time from boot to that line.

- [ ] **Step 4: Verify every model landed where its node looks for it**

```bash
cd /workspace/runpod-slim/ComfyUI
du -sh models/text_encoders models/diffusion_models models/vae models/checkpoints \
       models/loras models/vae_approx models/latent_upscale_models models/controlnet
find models -name '*.safetensors' | wc -l
ls -la custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Large/ \
       custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose/ \
       custom_nodes/comfyui_controlnet_aux/ckpts/hr16/DWPose-TorchScript-BatchSize5/
df -h /workspace
```

Expected: 11 safetensors under `models/` (10 base plus the ControlNet union model in `models/controlnet/`); the three preprocessor files present in their `ckpts/` folders at their exact sizes; `/workspace` comfortably under the 150 GB limit.

Whether `comfyui_controlnet_aux` actually *uses* those three files can only be seen once a ControlNet generation has run — the preprocessors load on first use, not at boot. That check is in Step 8.

- [ ] **Step 5: Test idempotence**

```bash
time bash /workspace/provision_minimax.sh
```

Expected: every model `[SKIP]`, every node pack `[SKIP]`, no restart, finishes in well under a minute.

- [ ] **Step 6: Test resume after a corrupt file**

```bash
truncate -s 1000000 /workspace/runpod-slim/ComfyUI/models/vae/minimax_h3_audio_vae_fp32.safetensors
bash /workspace/provision_minimax.sh 2>&1 | grep -A2 minimax_h3_audio_vae_fp32
```

Expected: `[WARN] discarding incomplete`, then a re-download, then `✓`. This proves the size check catches corruption that ComfyUI would otherwise half-load.

- [ ] **Step 7: Resolve the SAM3 question if Task 6 left it open**

Open ComfyUI on port 8188, load `MINIMAX_H3_ULTRA_WORKFLOW-V3.json` from the workflow list, and look for red "missing node" boxes in the inpainting group. If `SAM3_VideoTrack` and friends are missing, find the pack that provides them, fork it, add it to `docs/minimax-node-pins.txt` and to `NODE_PACKS`, and re-run. If nothing is red, the nodes come from the image and there is nothing to do — record that in the spec.

- [ ] **Step 8: Generate a real video**

Load `MINIMAX_H3_ULTRA_WORKFLOW-V3.json`, use a short duration, and run it end to end. This is the only check that actually proves the template works.

Two workflow toggles must be set correctly or the run proves the wrong thing, per the user's own runbook:

- **`RF PATCH SAGE` → enabled.** SageAttention must be activated by exactly one route. `provision_minimax.sh` does not pass `--use-sage-attention`, so the workflow group is that route. Confirm first with `cat /workspace/runpod-slim/comfyui_args.txt`; if the flag turns out to be there after all, bypass the group instead.
- **`RF SPEEDUP` (Spectrum) → bypassed.** It trades visible quality for speed, and the runbook forbids combining it with the turbo LoRA. A validation run should measure the configuration actually used for final output.

Watch VRAM while it runs, in a second terminal:

```bash
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 5
```

Record the peak against the 48 GB card — it settles whether the hardware guidance in the spec is right.

Then the ControlNet run. Load `MINIMAX_H3_ULTRA_WORKFLOW-V3_CONTROLNET.json` and confirm first that it opens with **no red nodes** — `H3FunControlLoader`, `H3FunControlApply`, `DWPreprocessor` and `DepthAnythingV2Preprocessor` must all resolve, and the loader's dropdown must list `minimax_h3_fun_controlnet_union_pruned_bf16.safetensors`. Run a short clip with one pose or depth reference, with the same two toggles as above.

Now — after the preprocessors have actually loaded — confirm they used the pre-placed files rather than fetching their own:

```bash
grep -iE 'Failed to find .*ckpts|Downloading from huggingface' /workspace/provision_minimax.log || echo "ok: controlnet_aux downloaded nothing itself"
grep -i 'onnxruntime' /workspace/provision_minimax.log
```

The first must print the `ok` line; any hit means a preprocessor file sits at the wrong path and will be re-fetched every session. (ComfyUI writes to this log because phase 5 restarted it on first boot.) The second answers the spec's open question: a warning that onnxruntime lacks acceleration providers means DWPose runs on CPU. It still works, only slowly — record it, do not fix it here.

- [ ] **Step 9: Save the output, then terminate**

Download the generated video from JupyterLab at `/workspace/runpod-slim/ComfyUI/output` **before** terminating. Then terminate the pod.

- [ ] **Step 10: Record results and commit any fixes**

Update the spec's testing section with the real numbers: provisioning wall-clock time, peak VRAM, and whether SageAttention landed on v1 or v2++.

```bash
git add -A
git commit -m "docs: record end-to-end validation results

Provisioning time, peak VRAM on the RTX 6000 Ada, and the SageAttention
version the image actually supports."
git push origin main
```

---

## Notes for whoever executes this

- **Tasks 6 and 10 cost money and need a human.** Everything else runs locally for free. If you are an agent, stop at the start of those tasks and hand back.
- **Task 6 gates Task 7.** The `nvcc` answer decides whether half of phase 1 ships at all. Do not guess it.
- **Task 10 Step 1 is a hard prerequisite** for every remaining step: the pod fetches from `main`, so the branch must be merged first.
- The workflow JSONs live at `C:/Users/Trabajo/OneDrive/Mis_Proyectos/4ADULTZ/documentos/Minimax/` on the user's machine. They are paid content: they go to the private HF mirror and nowhere else.
