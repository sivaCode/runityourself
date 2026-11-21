#!/bin/bash
# Remove LM Studio's llmster and lms, and every model you downloaded with them: stop the engine, delete ~/.lmstudio
# (models included: they are gigabytes), ~/.lmstudio-home-pointer, and take the PATH lines out of your shell profiles.
# The Mac is put back as install.sh found it (.state/before.env): a profile that existed is left byte for byte as it
# was, one the installer created is deleted, and Wi-Fi is switched back on if it was on before.
# Works from any state: installed or not, engine running or not, half-finished download or not.
#   ./uninstall.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
problems=0
note() { echo "note: $*"; }
bad()  { echo "PROBLEM: $*"; problems=$((problems + 1)); }

# Without a saved state (you ran the official installer yourself): remove LM Studio's files, keep the rest
LMS_HOME_EXISTED=no POINTER_EXISTED=no CACHE_HOME_EXISTED=no DOT_CACHE_EXISTED=yes WIFI_WAS=""
if [[ -f "$STATE" ]]; then source "$STATE"; else note "no saved state: removing LM Studio's files and PATH lines only"; fi
if [[ "$LMS_HOME_EXISTED" == yes && ! -f "$STATE_DIR/ours" ]]; then
  note "~/.lmstudio was there before install.sh ran: left alone"; exit 0
fi

# 0. Wi-Fi back on if a take left it off (the offline step turns it off)
if [[ "$WIFI_WAS" == On ]] && networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | grep -q 'Off$'; then
  if networksetup -setairportpower "$WIFI_DEV" on; then
    # it takes ~10 s to rejoin; wait (max 30 s) so a next take's hidden setup finds the network
    for i in $(seq 1 15); do limit 3 curl -fsS -o /dev/null https://lmstudio.ai/install.sh 2>/dev/null && break; sleep 2; done
    note "Wi-Fi switched back on"
  else
    bad "could not switch Wi-Fi back on"
  fi
fi

# 1. The engine and its workers
if [[ -x "$LMS" ]]; then
  limit 60 "$LMS" unload --all >/dev/null 2>&1 || true
  limit 60 "$LMS" daemon down >/dev/null 2>&1 || true
fi
for i in 1 2 3 4 5 6 7 8 9 10; do lms_running || break; sleep 1; done
if lms_running; then
  pkill -x llmster 2>/dev/null; pkill -f "$LMS_HOME/" 2>/dev/null; sleep 2
  lms_running && { pkill -9 -x llmster 2>/dev/null; pkill -9 -f "$LMS_HOME/" 2>/dev/null; sleep 1; }
fi
lms_running && bad "LM Studio processes are still running: $(pgrep -fl -i 'llmster|lmstudio' | mask | tr '\n' ';')"

# 2. The files
rm -rf "$LMS_HOME" || bad "could not delete ~/.lmstudio"
[[ "$POINTER_EXISTED" == yes ]] || rm -f "$POINTER"
[[ "$CACHE_HOME_EXISTED" == yes ]] || rm -rf "$CACHE_HOME"
[[ "$DOT_CACHE_EXISTED" == yes ]] || rmdir "$HOME/.cache" 2>/dev/null || true

# 3. The PATH lines in the shell profiles
for f in "${PROFILES[@]}"; do
  p="$HOME/$f"; [[ -f "$p" ]] || continue
  key="PROFILE_$(echo "$f" | tr -c 'A-Za-z0-9\n' '_')"; was="${!key:-unknown}"
  saved="$STATE_DIR/profiles/$(basename "$f")"
  (( $(path_block_count "$p") > 0 )) || [[ "$was" == absent ]] || continue
  strip_path_block "$p"
  if [[ "$was" == absent ]]; then
    if [[ -s "$p" ]]; then note "~/$f was created by the installer but now has other lines: kept, LM Studio lines removed"
    else rm -f "$p"; fi
  elif [[ "$was" != unknown && "$(shasum -a 256 "$p" | awk '{print $1}')" != "$was" ]]; then
    if [[ -f "$saved" ]] && (( $(path_block_count "$p") == 0 )) && cmp -s "$saved" <(head -c "$(wc -c < "$saved")" "$p") &&
       [[ -z "$(tail -c +$(( $(wc -c < "$saved") + 1 )) "$p" | tr -d '\n')" ]]; then
      cat "$saved" > "$p"       # only blank lines differ: back to the exact bytes it had
    else
      note "~/$f changed since the install (not by LM Studio): only the LM Studio lines were removed"
    fi
  fi
  (( $(path_block_count "$p" 2>/dev/null || echo 0) == 0 )) || bad "the LM Studio PATH block is still in ~/$f"
done

# 4. Nothing left behind
[[ -e "$LMS_HOME" ]] && bad "~/.lmstudio is still there"
[[ "$POINTER_EXISTED" != yes && -e "$POINTER" ]] && bad "~/.lmstudio-home-pointer is still there"
agents="$(ls "$HOME/Library/LaunchAgents" 2>/dev/null | grep -i -E 'lmstudio|llmster|elementlabs' || true)"
[[ -n "$agents" ]] && bad "a LaunchAgent is still there: $agents"

if (( problems )); then echo "uninstall finished with $problems problem(s)"; exit 1; fi
rm -rf "$STATE_DIR"
echo "removed: llmster, lms, the models, the PATH lines; the Mac is as install.sh found it"
