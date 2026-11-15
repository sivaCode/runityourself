#!/bin/bash
# Put the Mac back as install.sh found it. On the test Mac that was: the Ollama formula installed,
# no models, and the service in the same started/stopped state as before.
set -euo pipefail

MODELS=(gemma3:1b qwen3.5:2b-q4_K_M llama3.2:3b)
API="http://127.0.0.1:11434"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/.state/before.env"

FORMULA_WAS_INSTALLED=yes; SERVICE_WAS_STARTED=no
[[ -f "$STATE" ]] && source "$STATE"

if command -v ollama >/dev/null; then
  # rm needs a server. Use the one already running (the session `ollama serve`); otherwise start one for this
  # script only. Not `brew services start`: that registers a login item and macOS shows a background notice.
  if ! curl -fsS "$API/api/version" >/dev/null 2>&1; then
    ollama serve >/dev/null 2>&1 &
    for _ in $(seq 1 30); do curl -fsS "$API/api/version" >/dev/null 2>&1 && break; sleep 1; done
  fi
  for m in "${MODELS[@]}"; do ollama stop "$m" >/dev/null 2>&1 || true; ollama rm "$m" 2>/dev/null || true; done
  left="$(ollama list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ' || true)"
  [[ "$left" == "0" ]] || echo "note: $left other model(s) remain; they were not added by install.sh"
fi

# Stop the session server (`ollama serve` from the guide, or the one started above) so port 11434 is free.
brew services stop ollama >/dev/null 2>&1 || true
pkill -f 'ollama serve' 2>/dev/null || true
for _ in $(seq 1 10); do pgrep -f 'ollama serve' >/dev/null || break; sleep 1; done
rm -f /tmp/ollama.log
# Only if it was a login service before does it go back to brew services.
[[ "$SERVICE_WAS_STARTED" == yes ]] && { brew services start ollama >/dev/null 2>&1 || true; }
[[ "$FORMULA_WAS_INSTALLED" == yes ]] || brew uninstall ollama

# ~/.ollama was created by this install (server key, history, empty model folders): remove it only if it did not
# exist before and no model files are left in it. Anything else in there is kept.
D="$HOME/.ollama"
if [[ "${OLLAMA_DIR_EXISTED:-yes}" == no && "$SERVICE_WAS_STARTED" != yes && -d "$D" ]]; then
  if [[ -z "$(find "$D/models" -type f 2>/dev/null | head -1)" ]]; then
    rm -rf "$D/models"; rm -f "$D/id_ed25519" "$D/id_ed25519.pub" "$D/history" "$D/cache/model-recommendations.json"
    rmdir "$D/cache" 2>/dev/null || true
    rmdir "$D" 2>/dev/null || echo "note: $D kept, it holds other files"
  else
    echo "note: $D kept, it still holds model files"
  fi
fi

# `|| true`: with pipefail, brew list fails when the formula is not installed (found state "no formula"), and set -e
# would end the script here with exit 1 before the state file is removed.
now_ver="$(brew list --versions ollama 2>/dev/null | awk '{print $2}' || true)"
if [[ -n "${FOUND_VERSION:-}" && "${FOUND_VERSION:-}" != none && -n "$now_ver" && "$now_ver" != "$FOUND_VERSION" ]]; then
  echo "note: ollama was $FOUND_VERSION before; the formula is now $now_ver (Homebrew installs the current version)"
fi
rm -f "$STATE"
echo "uninstalled (formula kept: $FORMULA_WAS_INSTALLED, service started: $SERVICE_WAS_STARTED)"
