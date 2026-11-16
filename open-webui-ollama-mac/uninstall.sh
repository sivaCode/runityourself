#!/bin/bash
# Put the Mac back the way install.sh found it, from any state: installed or not, servers
# running or not, half-finished install or not. It deletes Open WebUI with its data (chats, uploads): back up
# ~/open-webui/data first if you want to keep them.
# With .state/ (saved before the install): models, formulae, caches and ~/.ollama that were not there before are
# removed too. Without .state/: only the servers are stopped and a ~/open-webui made by install.sh is removed.
set -uo pipefail                                   # no -e: something already gone must never stop the clean-up
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

note() { echo "note: $*" | say_home; }
have_state=no
OLLAMA_WAS_RUNNING=no; MODELS_BEFORE=""; OLLAMA_DIR_EXISTED=yes; OWUI_HOME_EXISTED=yes
PIP_CACHE_EXISTED=yes; HF_CACHE_EXISTED=yes
if [[ -f "$STATE" ]]; then source "$STATE"; have_state=yes; else note "no saved state (.state/before.env): servers stopped and a marked ~/open-webui removed, nothing else"; fi
was_before() { grep -qx "$1" "$STATE_DIR/formulae-before.txt" 2>/dev/null; }

# 1. Open WebUI: stop it, then remove its folder (venv, data, logs, secret key, admin login)
stop_owui
if [[ -d "$OWUI_HOME" ]]; then
  if [[ -f "$OWUI_MARK" || ( "$have_state" == yes && "$OWUI_HOME_EXISTED" == no ) ]]; then
    rm -rf "$OWUI_HOME"
  else
    note "$OWUI_HOME kept: it was there before and was not created by install.sh"
  fi
fi

# 2. Caches the pip install and the first start created (only those that did not exist before)
if [[ "$have_state" == yes ]]; then
  [[ "$PIP_CACHE_EXISTED" == no && -d "$PIP_CACHE" ]] && rm -rf "$PIP_CACHE"
  if [[ "$HF_CACHE_EXISTED" == no ]]; then
    rm -rf "$HF_CACHE"
  elif [[ -d "$HF_CACHE" ]]; then
    # Anything up to two levels deep (hub/models--…) that wasn't in the saved list is ours.
    hf_new() { ! grep -qxF "$1" "$STATE_DIR/hf-cache-before.txt" 2>/dev/null; }
    while IFS= read -r e; do
      if hf_new "$e"; then rm -rf "${HF_CACHE:?}/$e"
      elif [[ -d "$HF_CACHE/$e" ]]; then
        while IFS= read -r c; do hf_new "$e/$c" && rm -rf "${HF_CACHE:?}/$e/$c"; done < <(ls -A "$HF_CACHE/$e")
      fi
    done < <(ls -A "$HF_CACHE")
  fi
fi

# 3. Models that install.sh pulled (not the ones that were there before)
if [[ "$have_state" == yes ]] && command -v ollama >/dev/null 2>&1; then
  if ! ollama_up; then
    # `ollama rm` needs a server. A session-only one; never `brew services` (a login item + a macOS notice).
    ( exec nohup ollama serve </dev/null >"$OLLAMA_LOG" 2>&1 ) </dev/null >/dev/null 2>&1 &
    wait_http "$OLLAMA_API/api/version" 30 || note "ollama did not start; models not removed"
  fi
  for m in "${MODELS[@]}"; do
    [[ " $MODELS_BEFORE " == *" $m "* ]] && continue
    ollama stop "$m" >/dev/null 2>&1 || true
    ollama rm "$m" >/dev/null 2>&1 || true
  done
fi

# 4. Ollama's server: stop it unless it was already running before the install
if [[ "$OLLAMA_WAS_RUNNING" != yes ]]; then
  pkill -f 'ollama serve' 2>/dev/null || true
  for _ in $(seq 1 15); do pgrep -f 'ollama serve' >/dev/null || break; sleep 1; done
  pkill -9 -f 'ollama serve' 2>/dev/null || true
  rm -f "$OLLAMA_LOG"
fi

# 5. Formulae the install added (ollama, mlx-c, python@3.12 and any dependency that was not there before)
if [[ "$have_state" == yes ]]; then
  for f in "${MANAGED_FORMULAE[@]}"; do
    if formula_installed "$f" && ! was_before "$f"; then
      limit 300 brew uninstall --formula "$f" >/dev/null 2>&1 || note "brew uninstall $f failed (another formula may need it)"
    fi
  done
fi

# 6. ~/.ollama (server key, history, empty model folders) if this install created it and no model files are left
D="$HOME/.ollama"
if [[ "$have_state" == yes && "$OLLAMA_DIR_EXISTED" == no && -d "$D" ]]; then
  if [[ -z "$(find "$D/models/blobs" -type f 2>/dev/null | head -1)" ]]; then rm -rf "$D"
  else note "~/.ollama kept: it still holds model files"; fi
fi

# 7. What is left? Report, don't hide it.
left=0
pgrep -f 'open-webui serve' >/dev/null && { note "an open-webui server is still running"; left=1; }
lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1 && { note "port 8080 is still in use"; left=1; }
if [[ "$OLLAMA_WAS_RUNNING" != yes ]] && pgrep -f 'ollama serve' >/dev/null; then note "ollama serve is still running"; left=1; fi
[[ -f "$OWUI_MARK" ]] && { note "$OWUI_HOME is still there"; left=1; }

rm -rf "$STATE_DIR"                                # the found state has been restored; a new install saves a new one
if [[ "$left" == 0 ]]; then echo "uninstalled (Mac as found; saved state used: $have_state)"; else echo "uninstall incomplete"; exit 1; fi
