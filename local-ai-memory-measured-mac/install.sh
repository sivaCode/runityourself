#!/bin/bash
# Local AI memory, measured: Ollama on an Apple silicon Mac (Homebrew formula), a session server on
# 127.0.0.1 and one small model to start with. Idempotent: safe to run again in any state.
# Tested versions are listed in README.md.
#
# Safe defaults:
#   - the server runs for this session only (`ollama serve` in the background, log in /tmp/ollama.log);
#     no `brew services`, no login item, no launchctl, no sudo;
#   - it listens on 127.0.0.1 only: OLLAMA_HOST and the memory settings below are cleared for it, so the
#     numbers you measure are Ollama's defaults (context 4096, one parallel slot, f16 KV cache);
#   - nothing system-wide is changed (the GPU memory limit `iogpu.wired_limit_mb` is only ever read).
set -euo pipefail

PINNED_VERSION="${PINNED_VERSION:-0.40.16}"
START_MODELS=(gemma3:1b)                         # 806 MB; the other models are pulled one at a time later
MAX_MODEL_BYTES=$((5 * 1000 * 1000 * 1000))      # 5 GB per model (cap)
MIN_FREE_GB=20                                   # the Mac keeps 20 GB free
API="http://127.0.0.1:11434"
SERVER_LOG="/tmp/ollama.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/.state"
MODELS_DIR="${OLLAMA_MODELS:-$HOME/.ollama/models}"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_ENV_HINTS=1

fail() { echo "INSTALL FAILED: $*" >&2; exit 1; }
free_gb() { df -g / | awk 'NR==2 {print $4}'; }
api_up() { curl -fsS --max-time 2 "$API/api/version" >/dev/null 2>&1; }
# Time-box a long command (macOS has no `timeout`): limit <seconds> <command…>
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }
# Model tags present on disk, read from the manifests (works with or without a running server).
tags_on_disk() {
  local d="$MODELS_DIR/manifests/registry.ollama.ai/library"
  [[ -d "$d" ]] || return 0
  (cd "$d" && find . -type f | sed 's|^\./||; s|/|:|' | sort | tr '\n' ' ')
}

# 1. Requirements
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "needs an Apple silicon Mac"
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "needs macOS 14 (Sonoma) or newer"
command -v brew >/dev/null || fail "Homebrew not found (https://brew.sh)"
command -v curl >/dev/null || fail "curl not found"
(( $(free_gb) >= MIN_FREE_GB + 6 )) || fail "need $((MIN_FREE_GB + 6)) GB free (largest model 4.9 GB + the 20 GB floor)"

# 2. Remember how the Mac was found, so uninstall.sh can put it back (written once, never overwritten).
mkdir -p "$STATE"
if [[ ! -f "$STATE/before.env" ]]; then
  formula=no; found_ver=none
  if brew list --formula ollama >/dev/null 2>&1; then
    formula=yes; found_ver="$(brew list --versions ollama | awk '{print $2}')"
  fi
  dir=no; [[ -d "$HOME/.ollama" ]] && dir=yes
  server=no; api_up && server=yes
  printf 'FORMULA_WAS_INSTALLED=%s\nFOUND_VERSION=%s\nOLLAMA_DIR_EXISTED=%s\nSERVER_WAS_RUNNING=%s\nMODELS_BEFORE="%s"\n' \
    "$formula" "$found_ver" "$dir" "$server" "$(tags_on_disk)" > "$STATE/before.env"
fi
echo "found state (.state/before.env):"; sed 's/^/  /' "$STATE/before.env"

# 3. Ollama, the Homebrew formula (no self-update, no confirmation prompt, so the tested version stays put)
brew list --cask ollama-app >/dev/null 2>&1 && fail "the ollama-app cask is installed; this guide uses the formula"
if ! brew list --formula ollama >/dev/null 2>&1; then
  t0=$SECONDS
  limit 900 brew install ollama || { echo "brew install failed or timed out; retrying once"; limit 900 brew install ollama; }
  echo "brew install ollama took $((SECONDS - t0)) s"
fi
ver="$(ollama -v 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -1)"
[[ "$ver" == "$PINNED_VERSION" ]] || fail "ollama $ver installed, $PINNED_VERSION expected (set PINNED_VERSION to accept)"

# 4. The server, for this session only, on 127.0.0.1:11434 with default memory settings
if api_up; then
  echo "server already answering on $API (left as it is)"
else
  nohup env -u OLLAMA_HOST -u OLLAMA_CONTEXT_LENGTH -u OLLAMA_NUM_PARALLEL -u OLLAMA_KV_CACHE_TYPE \
    -u OLLAMA_FLASH_ATTENTION -u OLLAMA_MAX_LOADED_MODELS -u OLLAMA_KEEP_ALIVE \
    ollama serve >>"$SERVER_LOG" 2>&1 </dev/null &
  for _ in $(seq 1 30); do api_up && break; sleep 1; done
  api_up || fail "server did not answer on $API (see $SERVER_LOG)"
  echo "started ollama serve for this session (log: $SERVER_LOG)"
fi

# 5. The starting model (explicit tag, time-boxed, retried once; size checked from the server's own numbers)
for m in "${START_MODELS[@]}"; do
  t0=$SECONDS
  limit 1200 ollama pull "$m" || { echo "pull $m failed or timed out; retrying once"; limit 1200 ollama pull "$m"; }
  echo "pull $m took $((SECONDS - t0)) s"
done
/usr/bin/python3 - "$API" "$MAX_MODEL_BYTES" "${START_MODELS[@]}" <<'PY'
import json, sys, urllib.request
api, max_one, want = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
tags = {m["name"]: m["size"] for m in json.load(urllib.request.urlopen(api + "/api/tags"))["models"]}
for m in want:
    if m not in tags: sys.exit(f"INSTALL FAILED: {m} missing after the pull")
    if tags[m] > max_one: sys.exit(f"INSTALL FAILED: {m} is {tags[m]} bytes (> 5 GB cap)")
    print(f"{m}: {tags[m]} bytes on disk")
PY
(( $(free_gb) >= MIN_FREE_GB )) || fail "less than $MIN_FREE_GB GB free after the pull"

echo "installed (ollama $ver, server on 127.0.0.1:11434, models: ${START_MODELS[*]})"
