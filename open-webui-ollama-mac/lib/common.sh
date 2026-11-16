#!/bin/bash
# Shared settings and helpers for install.sh, verify.sh and uninstall.sh (sourced, not run).
# Open WebUI from PyPI in a Python 3.12 venv, next to a native Ollama (Homebrew formula). No Docker, no sudo,
# no `brew services`, no launchctl: both servers run in the background of this session only, bound to 127.0.0.1.

OWUI_VERSION="${OWUI_VERSION:-0.13.3}"             # pip install open-webui==OWUI_VERSION
OLLAMA_VERSION="${OLLAMA_VERSION:-0.40.16}"        # the Homebrew formula's version (T1 filmed the same)
MODELS=(gemma3:1b llama3.2:3b qwen3.5:2b-q4_K_M)   # T1's three models
PY_FORMULA="python@3.12"                           # Open WebUI supports 3.11 and 3.12, not 3.13
PY="/opt/homebrew/opt/python@3.12/bin/python3.12"

OWUI_HOME="${OWUI_HOME:-$HOME/open-webui}"         # everything Open WebUI owns: venv/, data/, logs/, secret key
VENV="$OWUI_HOME/venv"
OWUI_DATA="$OWUI_HOME/data"                        # DATA_DIR: database, uploads, vector store, model caches
OWUI_LOG="$OWUI_HOME/logs/serve.log"
OWUI_LOGIN="$OWUI_HOME/admin-login.txt"            # the throwaway admin install.sh creates (chmod 600)
OWUI_MARK="$OWUI_HOME/.installed-by-runityourself" # uninstall.sh only deletes an OWUI_HOME that has this file
OWUI_URL="http://127.0.0.1:8080"
OLLAMA_API="http://127.0.0.1:11434"
OLLAMA_LOG="/tmp/ollama.log"
PIP_CACHE="$HOME/Library/Caches/pip"
HF_CACHE="$HOME/.cache/huggingface"

# Formulae this guide may add, in a safe removal order (dependents first). Only the ones that were NOT there
# before the install are removed (the found list is saved in .state/formulae-before.txt).
# Ollama 0.40.16's bottle pulls in mlx-c, mlx and python@3.15 (pass 0, 15 Nov 2026).
MANAGED_FORMULAE=(ollama mlx-c mlx python@3.15 python@3.12 mpdecimal xz sqlite openssl@3 ca-certificates)

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$LIB_DIR/.." && pwd)"
STATE_DIR="$REPO_DIR/.state"
STATE="$STATE_DIR/before.env"

export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_ENV_HINTS=1
export PIP_DISABLE_PIP_VERSION_CHECK=1             # pip's upgrade notice prints the venv's /Users/<name> path

say_home() { sed "s#$HOME#~#g"; }                  # print paths as ~/…, never /Users/<name>
now() { /usr/bin/python3 -c 'import time; print(f"{time.time():.1f}")'; }
since() { /usr/bin/python3 -c "import sys,time; print(f'{time.time()-float(sys.argv[1]):.1f}')" "$1"; }
free_gb() { df -g / | awk 'NR==2 {print $4}'; }

# Run a command with a time limit (macOS has no `timeout`). Usage: limit SECONDS command…
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }

wait_http() {  # wait_http URL SECONDS: 0 once the URL answers 2xx
  local url="$1" secs="$2" i
  for ((i = 0; i < secs; i++)); do curl -fsS --max-time 3 "$url" >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}

# The installed open-webui version, from the package metadata. (`open-webui --version` prints nothing in 0.13.3:
# the option belongs to the `main` subcommand, `open-webui main --version`.)
owui_installed_version() {
  "$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("open-webui"))' 2>/dev/null || true
}

formula_installed() { brew list --formula "$1" >/dev/null 2>&1; }

ollama_up() { curl -fsS --max-time 3 "$OLLAMA_API/api/version" >/dev/null 2>&1; }
owui_up() { curl -fsS --max-time 3 "$OWUI_URL/health" >/dev/null 2>&1; }

start_ollama() {  # in the background of this session; the default bind is 127.0.0.1:11434
  ollama_up && return 0
  ( exec nohup ollama serve </dev/null >"$OLLAMA_LOG" 2>&1 ) </dev/null >/dev/null 2>&1 &
  wait_http "$OLLAMA_API/api/version" 30
}

owui_env() {  # the environment Open WebUI is started with (also printed in README.md)
  export DATA_DIR="$OWUI_DATA"
  export OLLAMA_BASE_URL="$OLLAMA_API"
  export ENABLE_OPENAI_API=False                   # no default OpenAI connection: the picker shows local models only
}

start_owui() {  # start from OWUI_HOME so its .webui_secret_key stays there (sessions survive restarts)
  owui_up && return 0
  mkdir -p "$OWUI_HOME/logs"
  # exec: the subshell becomes the server, and its own output goes nowhere. Before (gate passes 1-2, first run), an
  # in-between bash kept the caller's log open and wrote "Terminated: 15" into it after "exit 0" when the server was
  # stopped later.
  ( cd "$OWUI_HOME" && owui_env && exec nohup "$VENV/bin/open-webui" serve --host 127.0.0.1 --port 8080 \
      </dev/null >>"$OWUI_LOG" 2>&1 ) </dev/null >/dev/null 2>&1 &
  wait_http "$OWUI_URL/health" "${1:-600}"
}

stop_owui() {
  pkill -f 'open-webui serve' 2>/dev/null || true
  local i
  for ((i = 0; i < 30; i++)); do pgrep -f 'open-webui serve' >/dev/null || return 0; sleep 1; done
  pkill -9 -f 'open-webui serve' 2>/dev/null || true
}

# Save how the Mac was found, once (install.sh). uninstall.sh restores from it alone.
save_state() {
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE" ]] && return 0
  brew list --formula -1 2>/dev/null | sort > "$STATE_DIR/formulae-before.txt"
  local running=no; ollama_up && running=yes
  local models=""
  if command -v ollama >/dev/null 2>&1 && ollama_up; then
    models="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ' ')"
  elif [[ -d "$HOME/.ollama/models/manifests" ]]; then
    models="$(cd "$HOME/.ollama/models/manifests" && find . -type f | sed -E 's#^\./##' | awk -F/ '{print $(NF-1)":"$NF}' | tr '\n' ' ')"
  fi
  local d_ollama=no d_owui=no d_pip=no d_hf=no
  [[ -d "$HOME/.ollama" ]] && d_ollama=yes
  [[ -e "$OWUI_HOME" ]] && d_owui=yes
  [[ -d "$PIP_CACHE" ]] && d_pip=yes
  [[ -d "$HF_CACHE" ]] && d_hf=yes
  # Two levels (e.g. hub/models--…): the first start downloads the embedding model into ~/.cache/huggingface/hub
  ( cd "$HF_CACHE" 2>/dev/null && find . -mindepth 1 -maxdepth 2 | sed 's#^\./##' | sort ) > "$STATE_DIR/hf-cache-before.txt"
  {
    echo "SAVED_AT='$(date '+%Y-%m-%d %H:%M:%S')'"
    echo "OLLAMA_WAS_RUNNING=$running"
    echo "MODELS_BEFORE='$models'"
    echo "OLLAMA_DIR_EXISTED=$d_ollama"
    echo "OWUI_HOME_EXISTED=$d_owui"
    echo "PIP_CACHE_EXISTED=$d_pip"
    echo "HF_CACHE_EXISTED=$d_hf"
  } > "$STATE"
}
