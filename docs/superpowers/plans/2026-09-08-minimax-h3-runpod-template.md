# MiniMax H3 Ultra V3 RunPod Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a RunPod template the user owns end to end for the MiniMax H3 Ultra V3 workflow — official base image, own provisioning script, own private model mirror, own forks of the fragile node packs.

**Architecture:** Two bash scripts in the existing public repo `adri738/vace-runpod`. `mirror_minimax.sh` runs once ever and copies 10 model files (83,169,189,972 bytes) from `Aitrepreneur/FLX` into a private HuggingFace repo. `provision_minimax.sh` runs on every pod boot, fetched by the Container Start Command, and installs SageAttention, 13 custom-node packs at pinned commits, the 10 models, and both workflow JSONs. Both scripts are self-contained single files (they are fetched by `curl` at boot, so they cannot depend on sibling files), but expose their pure functions for local unit testing via a `BASH_SOURCE` guard.

**Tech Stack:** Bash 4+, git, curl/aria2c/wget, HuggingFace `hf` CLI, ComfyUI, RunPod. Tests are plain bash with a tiny hand-rolled assertion harness — no bats, no python (the user's Windows machine has no `python` on PATH).

**Spec:** `docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md`

## Global Constraints

- Base image: `runpod/comfyui:1.4.7-cuda13.0` — pinned, never the floating `cuda13.0` tag.
- ComfyUI root on the pod: `/workspace/runpod-slim/ComfyUI`.
- Volume Disk 150 GB, Container Disk 25 GB, mount path `/workspace`, HTTP ports `8188,8888`, TCP `22`.
- GPU: RTX 6000 Ada (48 GB VRAM).
- Private mirror repo: `adri738/minimax-h3-ultra-v3`.
- Public GitHub repo: `adri738/vace-runpod`, branch `minimax-h3-template` during development; scripts must reach `main` before a pod can fetch them.
- **The two workflow JSONs are paid content and must NEVER be committed to the public GitHub repo.** They travel only through the private HF mirror. `.gitignore` must block them.
- The pod only ever holds a **read-only, single-repo** HF token. The write token is used by hand, once, and never stored in the template.
- All 10 models download every boot. There is no partial/lite profile.
- Scripts never use `set -e`. Failures accumulate in a `FAILED` array and are reported in a final summary, matching `provision_vace.sh` and `provision_sdxl.sh`.
- All side effects live inside functions. Top level defines constants and functions only, so tests can source the script safely.

---

## File Structure

| Path | Responsibility |
|---|---|
| `provision_minimax.sh` (create) | Boot-time provisioner. Phases 0-5. Self-contained, sourceable. |
| `mirror_minimax.sh` (create) | One-time mirror population. Self-contained, sourceable. |
| `docs/minimax-node-pins.txt` (create) | Single source of truth for the 13 node packs and their pinned commits. Embedded verbatim into `provision_minimax.sh`; a test asserts the two never drift. |
| `tests/helpers.sh` (create) | Dependency-free assertion harness plus safetensors fixture builders. |
| `tests/test_provision_minimax.sh` (create) | Unit tests for the pure functions of `provision_minimax.sh`. |
| `tests/run_tests.sh` (create) | Runs every `tests/test_*.sh`, exits non-zero on any failure. |
| `MINIMAX_INSTRUCTIONS.md` (create) | User-facing guide, sibling of `SDXL_INSTRUCTIONS.md`. |
| `README.md` (modify) | Add the third template to the intro. |
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

header_bad='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
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
MIRROR_REPO="${MINIMAX_HF_REPO:-adri738/minimax-h3-ultra-v3}"
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
MINIMAX_H3_ULTRA_TURBO_WORKFLOW-V3.json
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
git check-ignore -v MINIMAX_H3_ULTRA_TURBO_WORKFLOW-V3.json
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
MIRROR_REPO="${MINIMAX_HF_REPO:-adri738/minimax-h3-ultra-v3}"
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

    if ! hf download "$SOURCE_REPO" "$name" --local-dir "$WORK" >/dev/null; then
        FAILED+=("download: $name")
        return 1
    fi

    got_size="$(stat -c%s "$local_file" 2>/dev/null)"
    if [[ "$got_size" != "$bytes" ]]; then
        log "   ✗ size mismatch: expected $bytes, got ${got_size:-none}"
        FAILED+=("size: $name")
        return 1
    fi

    log "   verifying sha256 (this is the only time we pay for it)"
    got_sha="$(sha256sum "$local_file" | awk '{print $1}')"
    if [[ "$got_sha" != "$want_sha" ]]; then
        log "   ✗ sha256 mismatch"
        log "     expected $want_sha"
        log "     got      $got_sha"
        FAILED+=("sha256: $name")
        return 1
    fi

    log "   uploading to $MIRROR_REPO"
    if ! HF_TOKEN="$HF_WRITE_TOKEN" hf upload "$MIRROR_REPO" "$local_file" "$name" \
        --repo-type model >/dev/null; then
        FAILED+=("upload: $name")
        return 1
    fi

    rm -f "$local_file"
    log "   ✓ $name mirrored"
}

upload_workflows() {
    local f
    log "──── workflow JSONs ────"
    for f in MINIMAX_H3_ULTRA_WORKFLOW-V3.json MINIMAX_H3_ULTRA_TURBO_WORKFLOW-V3.json; do
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
    done
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

### Task 6: Pod session #1 — reconnaissance and mirror

**Files:**
- Modify: `docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md` (record the answers in "Open questions")
- Modify: `provision_minimax.sh` only if reconnaissance contradicts an assumption

**Interfaces:**
- Produces: answers to the three open questions, and a populated mirror. Task 7's phase 1 branches on the `nvcc` answer; the Container Start Command in Task 9 depends on the entrypoint answer.

This is the first of two paid pod sessions. Both jobs are done in one session on purpose — reconnaissance takes 5 minutes, the mirror takes 15-25, and a CPU-only pod costs about $0.10/hour.

- [ ] **Step 1: Deploy a reconnaissance pod**

RunPod console → Pods → Deploy. Use a **CPU-only pod** (cheapest available). Set:

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
grep -rl "SAM3_VideoTrack" / --include="*.py" 2>/dev/null | head -5 || echo "NOT FOUND ANYWHERE"

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
- **`NOT FOUND ANYWHERE`** for SAM3 → the inpainting half of the workflow needs a 14th node pack that the creator's installer does not clone. Note it, finish the rest of the plan, and resolve it in Task 10 by loading the workflow and reading which node types ComfyUI reports as missing.

- [ ] **Step 3: Run the mirror**

At this point `mirror_minimax.sh` exists only on the local branch, which has not been pushed —
there is nothing to `curl` yet. Get it onto the pod the same way you already move the
creator's installer: drag `mirror_minimax.sh` from the repo folder on your PC into
JupyterLab's `/workspace` panel.

(If the branch has been pushed to GitHub by then, `curl -fsSL
https://raw.githubusercontent.com/adri738/vace-runpod/minimax-h3-template/mirror_minimax.sh -o
mirror_minimax.sh` works instead. Either route is fine.)

Then, in the pod terminal:

```bash
cd /workspace
export HF_WRITE_TOKEN=hf_xxxxxxxx   # paste a WRITE token from huggingface.co/settings/tokens
bash mirror_minimax.sh
```

Expected final line: `✅ mirror complete`. If any file fails, re-run — it resumes.

The two workflow JSONs are not on the pod, so they will be reported as skipped. That is expected; Step 4 handles them.

- [ ] **Step 4: Upload the two workflow JSONs**

Drag both files from the PC into JupyterLab's `/workspace` folder, then:

```bash
cd /workspace
bash mirror_minimax.sh
```

The models are already mirrored and get skipped in seconds; only the JSONs upload. Expected: two `✓ ... uploaded` lines.

- [ ] **Step 5: Confirm the mirror holds all 12 files**

```bash
curl -s -H "Authorization: Bearer ${HF_WRITE_TOKEN}" \
  "https://huggingface.co/api/models/adri738/minimax-h3-ultra-v3/tree/main?recursive=1" \
  | grep -oE '"path": "[^"]*"' | sort
```

Expected: 10 `.safetensors` plus 2 `.json`.

- [ ] **Step 6: Create the read-only token for the template**

At https://huggingface.co/settings/tokens create a **fine-grained** token with:
- Repository access: **only** `adri738/minimax-h3-ultra-v3`
- Permissions: **read only**

Save it — Task 9's template configuration needs it. Do not reuse the write token.

- [ ] **Step 7: Terminate the pod, then record the findings**

Terminate the pod in the RunPod console (the mirror lives on HuggingFace now; nothing on the pod is needed).

Replace the "Open questions to resolve during implementation" section of the spec with the answers, then:

```bash
git add docs/superpowers/specs/2026-09-08-minimax-h3-runpod-template-design.md
git commit -m "docs: record reconnaissance answers from pod session 1

Resolves nvcc availability, the image entrypoint, and the origin of the
SAM3 nodes. Mirror is populated with all 10 models and both workflows."
```

---

### Task 7: Provisioning phases 0-2 — wait, SageAttention, node packs

**Files:**
- Modify: `provision_minimax.sh`
- Modify: `tests/test_provision_minimax.sh`

**Interfaces:**
- Consumes: `sanitize_requirements` (Task 3), `docs/minimax-node-pins.txt` (Task 1), the `nvcc` answer (Task 6).
- Produces: `find_comfy_python` (echoes a python path), `NODE_PACKS` (newline string of `dir|url|sha`), `node_pack_lines`, `phase0_wait_for_comfyui`, `phase1_sageattention`, `phase2_node_packs`. `NODES_CHANGED` is set to `1` when phase 2 modified anything; Task 8's phase 5 reads it to decide whether ComfyUI needs restarting.

**Forward dependency, on purpose:** `phase1_sageattention` calls `fetch_mirror_file`, which Task 8 defines. Bash resolves function names at call time, so the finished script is correct — but the script is **not runnable on a pod until Task 8 lands**. Unit tests pass in the meantime because they exercise only the pure functions. Do not try to run the script end to end between these two tasks.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_provision_minimax.sh`, immediately before the final `finish` call:

```bash
echo "-- node pack manifest --"

assert_eq "13 node packs" "13" "$(node_pack_lines | grep -c .)"

assert_eq "every line has three fields" "0" \
    "$(node_pack_lines | awk -F'|' 'NF != 3' | grep -c .)"

assert_eq "every commit is a 40-char sha" "0" \
    "$(node_pack_lines | awk -F'|' '$3 !~ /^[0-9a-f]{40}$/' | grep -c .)"

assert_eq "every url is a github https clone url" "0" \
    "$(node_pack_lines | awk -F'|' '$2 !~ /^https:\/\/github\.com\/.+\.git$/' | grep -c .)"

assert_eq "no duplicate directories" "0" \
    "$(node_pack_lines | cut -d'|' -f1 | sort | uniq -d | grep -c .)"

assert_eq "the nine fragile packs point at adri738 forks" "9" \
    "$(node_pack_lines | grep -c '|https://github.com/adri738/')"

# The embedded copy must never drift from the reviewable source of truth.
assert_eq "embedded pins match docs/minimax-node-pins.txt" \
    "$(grep -vE '^[[:space:]]*(#|$)' docs/minimax-node-pins.txt | sort | tr '\n' ' ')" \
    "$(node_pack_lines | sort | tr '\n' ' ')"
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash tests/test_provision_minimax.sh
```

Expected: FAIL — `node_pack_lines: command not found`.

- [ ] **Step 3: Add the node manifest and phases 0-2**

First embed the pins. Add to `provision_minimax.sh` after `workflow_lines`, pasting the body of `docs/minimax-node-pins.txt` verbatim between the quotes (the test in Step 1 enforces that they match):

```bash
# Custom-node packs: directory|clone url|pinned commit.
#
# Kept identical to docs/minimax-node-pins.txt, which is the reviewable
# source of truth; tests/test_provision_minimax.sh fails if they drift.
# Nine of these point at forks under adri738 so a deleted upstream cannot
# break the template. Pinning protects against breaking changes; forking
# protects against deletion. Both are needed.
NODE_PACKS='
<paste the non-comment lines of docs/minimax-node-pins.txt here>
'

node_pack_lines() {
    printf '%s\n' "$NODE_PACKS" | grep -vE '^[[:space:]]*(#|$)'
}
```

Then add the phases, after `node_pack_lines`:

```bash
setup_logging() {
    mkdir -p "$(dirname "$LOG")" "$STAGING"
    exec > >(tee -a "$LOG") 2>&1
}

find_comfy_python() {
    local candidate
    for candidate in \
        "${COMFY_PYTHON:-}" \
        "$COMFY_ROOT/venv/bin/python" \
        "$COMFY_ROOT/.venv/bin/python" \
        "/workspace/runpod-slim/venv/bin/python"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v python3
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

    PYTHON="$(find_comfy_python)"
    log "ComfyUI root : $COMFY_ROOT (ready after ${waited}s)"
    log "ComfyUI python: $PYTHON"
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

    if command -v nvcc >/dev/null 2>&1; then
        log "• nvcc present — building SageAttention 2++ in the background"
        log "  (ComfyUI stays usable on v1 while this runs)"
        nohup bash "$SCRIPT_PATH" --build-sage >> "$LOG" 2>&1 </dev/null &
    else
        log "• no nvcc in this image — staying on SageAttention v1"
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
    done <<< "$(node_pack_lines)"

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
    done <<< "$(node_pack_lines)"

    # VideoHelperSuite needs this and it touches nothing GPU-related.
    "$PYTHON" -m pip install --no-input --prefer-binary imageio-ffmpeg >/dev/null 2>&1 \
        || FAILED+=("pip: imageio-ffmpeg")
}
```

Also add `SCRIPT_PATH` next to the other constants at the top of the file, so the background build can re-invoke the script by an absolute path:

```bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
```

If Task 6 reported `NO NVCC`, delete the `if command -v nvcc` branch of `phase1_sageattention` and the whole `build_sage_wheel` function rather than shipping code that can never run.

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
all 13 node packs at pinned commits with sanitized requirements."
```

---

### Task 8: Provisioning phases 3-5 — models, workflows, restart

**Files:**
- Modify: `provision_minimax.sh`

**Interfaces:**
- Consumes: `safetensors_ok` (Task 2), `manifest_lines` / `workflow_lines` (Task 4), `NODES_CHANGED` (Task 7).
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

# download_model <filename> <subdir> <bytes> <status dir>
download_model() {
    local name="$1" subdir="$2" bytes="$3" status="$4"
    local dest="$COMFY_ROOT/models/$subdir/$name"
    local stage="$STAGING/${name}.part"

    mkdir -p "$(dirname "$dest")"

    if safetensors_ok "$dest" "$bytes"; then
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

    if fetch_mirror_file "$name" "$stage" && safetensors_ok "$stage" "$bytes"; then
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
    local status name subdir bytes running=0 failures

    log ""
    log "──── phase 3: models ────"
    log "10 files, 83,169,189,972 bytes, ${MODEL_PARALLEL} at a time"

    status="$STAGING/status"
    rm -rf "$status"
    mkdir -p "$status"

    while IFS='|' read -r name subdir bytes; do
        [[ -n "$name" ]] || continue
        download_model "$name" "$subdir" "$bytes" "$status" &
        running=$(( running + 1 ))
        if (( running >= MODEL_PARALLEL )); then
            wait -n 2>/dev/null || true
            running=$(( running - 1 ))
        fi
    done <<< "$(manifest_lines)"

    wait

    failures="$(find "$status" -name 'fail.*' | wc -l | tr -d ' ')"
    if [[ "$failures" != "0" ]]; then
        # Process substitution, not a pipe: a piped while-loop runs in a
        # subshell and its appends to FAILED would be discarded.
        while IFS= read -r entry; do
            FAILED+=("model: ${entry#fail.}")
        done < <(find "$status" -name 'fail.*' -exec basename {} \;)
    fi

    # The HF CLI keeps its own copy under the staging dir; 77 GB is not
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
    done <<< "$(workflow_lines)"
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
    done <<< "$(node_pack_lines)"

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

    log ""
    log "════ MiniMax H3 provisioning started (${1:-manual}): $(date) ════"

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

- [ ] **Step 3: Run the tests and syntax check**

```bash
bash tests/run_tests.sh
bash -n provision_minimax.sh && echo "syntax ok"
```

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

Downloads all 10 models from the private mirror in parallel with staged,
size-validated, atomic writes; places both workflows in ComfyUI's saved
list; restarts ComfyUI only when nodes changed and verifies all 13 packs
loaded before declaring success."
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

Match the voice and structure of `SDXL_INSTRUCTIONS.md`. It must contain:

1. **Deploy steps** — RunPod console → Pods → Deploy, GPU **RTX 6000 Ada (48 GB)**, template **minimax-h3**, On-Demand.
2. **A prominent warning, near the top:** *this pod is always terminated, never stopped — download every generated video before terminating, from JupyterLab at `/workspace/runpod-slim/ComfyUI/output`.*
3. **First-boot timing** — roughly 15-25 minutes, dominated by the 77 GB of models. Progress: Connect → JupyterLab (8888) → Terminal → `tail -f /workspace/provision_minimax.log`. Wait for `✅ MiniMax H3 provisioning finished`.
4. **Manual fallback**, if the log file never appears after ~5 minutes:

   ```
   cd /workspace && curl -fsSL https://raw.githubusercontent.com/adri738/vace-runpod/main/provision_minimax.sh -o provision_minimax.sh && bash provision_minimax.sh
   ```

5. **Using it** — Connect → HTTP Service port 8188. Both workflows are already in the workflow list (sidebar → Workflows); no drag and drop needed.
6. **The template settings table** exactly as in the spec, including the Container Start Command from Step 2 below.
7. **The one-time SageAttention wheel upload**, quoting the command the script prints, and explaining that doing it once makes every later pod skip a 15-30 minute build.
8. **Troubleshooting**, three symptoms with fixes: red "missing node" boxes (provisioning did not finish — check the log for ❌ lines, re-run the fallback, refresh the tab); a model missing from a dropdown (same fallback, it re-downloads only what is missing); `HF_TOKEN is not set` in the log (the template env var is missing or the token was revoked).
9. **How to bump the pinned image or node commits** deliberately: edit the version in the template, or regenerate `docs/minimax-node-pins.txt` with the Task 1 command and re-commit.

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

RunPod console → Templates → New Template. Fill in exactly the table from `MINIMAX_INSTRUCTIONS.md`, including the read-only `HF_TOKEN` created in Task 6 Step 6 and `MINIMAX_HF_REPO=adri738/minimax-h3-ultra-v3`. Name it `minimax-h3`.

- [ ] **Step 3: Deploy and watch the full provisioning run**

Deploy On-Demand on an RTX 6000 Ada. Then JupyterLab (8888) → Terminal:

```bash
tail -f /workspace/provision_minimax.log
```

Expected end state: `✅ MiniMax H3 provisioning finished`, with `✓ loaded:` for all 13 packs and no `❌` lines. Note the wall-clock time from boot to that line.

- [ ] **Step 4: Verify the models landed where ComfyUI expects them**

```bash
cd /workspace/runpod-slim/ComfyUI/models
du -sh text_encoders diffusion_models vae checkpoints loras vae_approx latent_upscale_models
find . -name '*.safetensors' | wc -l
df -h /workspace
```

Expected: 10 safetensors files, and `/workspace` comfortably under the 150 GB limit.

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

Load `MINIMAX_H3_ULTRA_TURBO_WORKFLOW-V3.json`, use a short duration, and run it end to end. This is the only check that actually proves the template works.

Watch VRAM while it runs, in a second terminal:

```bash
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 5
```

Record the peak against the 48 GB card — it settles whether the hardware guidance in the spec is right.

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
