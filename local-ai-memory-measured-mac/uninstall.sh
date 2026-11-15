#!/bin/bash
# Put the Mac back the way install.sh found it (.state/before.env), from any state: installed or not,
# server running or not, half-finished pulls included. Every step is guarded; nothing here stops on
# something that is already gone. Models you had before install.sh ran are kept.
set -uo pipefail

# Every model this episode pulls (install.sh, the measurements and the video's steps).
EPISODE_MODELS=(gemma3:1b qwen3.5:2b-q4_K_M llama3.2:3b llama3.2:3b-instruct-q8_0 qwen3.5:4b-q4_K_M llama3.1:8b)
API="http://127.0.0.1:11434"
SERVER_LOG="/tmp/ollama.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/.state/before.env"
D="$HOME/.ollama"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_ENV_HINTS=1

# Without a record, assume the safe side: keep the formula, the folder and any server.
FORMULA_WAS_INSTALLED=yes; FOUND_VERSION=none; OLLAMA_DIR_EXISTED=yes; SERVER_WAS_RUNNING=yes; MODELS_BEFORE=""
if [[ -f "$STATE" ]]; then
  source "$STATE"
else
  echo "note: no .state/before.env; keeping the formula, ~/.ollama and any server, removing only this episode's models"
fi

api_up() { curl -fsS --max-time 2 "$API/api/version" >/dev/null 2>&1; }
had_before() { [[ " $MODELS_BEFORE " == *" $1 "* ]]; }
serve_pids() { pgrep -f '(^|/)ollama serve$' 2>/dev/null || true; }

# 1. This episode's models (ollama rm needs a server; start a temporary one if none is running).
started_tmp=no
if command -v ollama >/dev/null; then
  if ! api_up; then
    nohup ollama serve >/dev/null 2>&1 </dev/null &
    started_tmp=yes
    for _ in $(seq 1 30); do api_up && break; sleep 1; done
  fi
  for m in "${EPISODE_MODELS[@]}"; do
    ollama stop "$m" >/dev/null 2>&1 || true
    if had_before "$m"; then echo "kept $m (it was there before install.sh)"; continue; fi
    ollama rm "$m" >/dev/null 2>&1 && echo "removed $m"
  done
  left="$(ollama list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')"
  [[ "${left:-0}" == "0" ]] || echo "note: $left model(s) remain; this episode did not add them"
fi

# 2. The session server: stop it unless one was already running before install.sh (or we have no record).
if [[ "$SERVER_WAS_RUNNING" != yes || "$started_tmp" == yes ]]; then
  for p in $(serve_pids); do kill "$p" 2>/dev/null || true; done
  for _ in $(seq 1 15); do [[ -z "$(serve_pids)" ]] && break; sleep 1; done
  for p in $(serve_pids); do kill -9 "$p" 2>/dev/null || true; done
  # Model runners the server started (they normally exit with it).
  pkill -f 'Cellar/ollama/.*/(llama-server|ollama runner)' 2>/dev/null || true
  [[ -z "$(serve_pids)" ]] && echo "server stopped" || echo "note: an ollama serve process is still running"
fi
[[ "$SERVER_WAS_RUNNING" != yes ]] && rm -f "$SERVER_LOG"

# 3. The formula: remove it only if install.sh added it.
if [[ "$FORMULA_WAS_INSTALLED" == no ]] && brew list --formula ollama >/dev/null 2>&1; then
  # Homebrew also removes the dependencies it brought in and nothing else needs (mlx-c and friends).
  brew uninstall ollama && echo "removed the ollama formula (it wasn't installed before)"
fi
now_ver="$(brew list --versions ollama 2>/dev/null | awk '{print $2}' || true)"
if [[ "$FOUND_VERSION" != none && -n "$now_ver" && "$now_ver" != "$FOUND_VERSION" ]]; then
  echo "note: ollama was $FOUND_VERSION before; the formula is now $now_ver (Homebrew installs the current version)"
fi

# 4. ~/.ollama: remove it only if install.sh created it and no model files are left in it.
if [[ "$OLLAMA_DIR_EXISTED" == no && -d "$D" ]]; then
  if [[ -z "$(find "$D/models/blobs" -type f ! -name '*-partial*' 2>/dev/null | head -1)" ]]; then
    rm -rf "$D" && echo "removed ~/.ollama (install.sh created it)"
  else
    echo "note: ~/.ollama kept, it still holds model files"
  fi
fi

# 5. Done: forget the record, so the next install.sh records the Mac afresh.
rm -f "$STATE"; rmdir "$HERE/.state" 2>/dev/null || true
echo "uninstalled (formula kept: $FORMULA_WAS_INSTALLED, ~/.ollama kept: $OLLAMA_DIR_EXISTED, server kept: $SERVER_WAS_RUNNING)"
exit 0
