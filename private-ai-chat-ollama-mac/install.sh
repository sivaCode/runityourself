#!/bin/bash
# Ollama on an Apple silicon Mac (Homebrew formula) + three small models. Idempotent.
# Tested versions are listed in README.md.
# Safe defaults: the server listens on 127.0.0.1 only; OLLAMA_HOST is never changed here.
set -euo pipefail

PINNED_VERSION="${PINNED_VERSION:-0.40.16}"
MODELS=(gemma3:1b qwen3.5:2b-q4_K_M llama3.2:3b)
MAX_MODEL_BYTES=$((5 * 1000 * 1000 * 1000))     # 5 GB per model (cap)
MAX_TOTAL_BYTES=$((6 * 1000 * 1000 * 1000))     # 6 GB all models (cap)
MIN_FREE_GB=20                                  # the Mac keeps 20 GB free
API="http://127.0.0.1:11434"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/.state"

fail() { echo "INSTALL FAILED: $*" >&2; exit 1; }
free_gb() { df -g / | awk 'NR==2 {print $4}'; }

# 1. Requirements
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "needs an Apple silicon Mac"
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "needs macOS 14 (Sonoma) or newer"
command -v brew >/dev/null || fail "Homebrew not found (https://brew.sh)"
command -v curl >/dev/null || fail "curl not found"
(( $(free_gb) >= MIN_FREE_GB + 6 )) || fail "need $((MIN_FREE_GB + 6)) GB free before pulling models"

# 2. Remember how the Mac was found, so uninstall.sh can put it back (written once).
mkdir -p "$STATE"
if [[ ! -f "$STATE/before.env" ]]; then
  formula=no; brew list --formula ollama >/dev/null 2>&1 && formula=yes
  service=no; brew services list | awk '$1=="ollama" && $2=="started"' | grep -q . && service=yes
  printf 'FORMULA_WAS_INSTALLED=%s\nSERVICE_WAS_STARTED=%s\n' "$formula" "$service" > "$STATE/before.env"
fi

# 3. Ollama (formula: no auto-update, so the filmed version stays put)
brew list --cask ollama-app >/dev/null 2>&1 && fail "the ollama-app cask is installed; this guide uses the formula"
brew list --formula ollama >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install ollama
ver="$(ollama -v 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -1)"
[[ "$ver" == "$PINNED_VERSION" ]] || fail "ollama $ver installed, $PINNED_VERSION expected (set PINNED_VERSION to accept)"

# 4. Background service, bound to localhost
brew services start ollama >/dev/null
for _ in $(seq 1 30); do curl -fsS "$API/api/version" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "$API/api/version" >/dev/null || fail "server did not answer on $API"

# 5. Models (explicit tags; caps checked from the server's own sizes)
for m in "${MODELS[@]}"; do ollama pull "$m"; done
/usr/bin/python3 - "$API" "$MAX_MODEL_BYTES" "$MAX_TOTAL_BYTES" "${MODELS[@]}" <<'PY'
import json, sys, urllib.request
api, max_one, max_all, want = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
tags = {m["name"]: m["size"] for m in json.load(urllib.request.urlopen(api + "/api/tags"))["models"]}
missing = [m for m in want if m not in tags]
if missing: sys.exit(f"INSTALL FAILED: models missing: {missing}")
for m in want:
    if tags[m] > max_one: sys.exit(f"INSTALL FAILED: {m} is {tags[m]} bytes (> 5 GB cap)")
total = sum(tags[m] for m in want)
if total > max_all: sys.exit(f"INSTALL FAILED: models total {total} bytes (> 6 GB cap)")
print(f"models total {total/1e9:.2f} GB")
PY
(( $(free_gb) >= MIN_FREE_GB )) || fail "less than $MIN_FREE_GB GB free after pulls"

echo "installed (ollama $ver, ${#MODELS[@]} models)"
