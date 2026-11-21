#!/bin/bash
# LM Studio without the desktop app: install llmster (LM Studio's headless engine) and the lms CLI with the official
# installer, start the engine, and download one small model. Idempotent: run it again and it skips what is done.
#   ./install.sh
# What it changes on your Mac (./uninstall.sh puts all of it back):
#   ~/.lmstudio/                  llmster 0.1.1-2 (3.8 GB), the lms CLI (bin/lms), the models you download (models/)
#   ~/.lmstudio-home-pointer      a one-line file naming that folder
#   ~/.zshrc                      two lines that add ~/.lmstudio/bin to your PATH (the file is created if missing)
# No account, no login, no desktop app, no login item or background service: the engine runs until you stop it
# (`lms daemon down`) or log out.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
stop() { echo "STOP: $*" >&2; exit 1; }

# 1. This Mac can run it (Apple Silicon, macOS 14 or newer) and has the room
[[ "$(uname -s)" == Darwin ]] || stop "this script is for macOS"
# A terminal running under Rosetta reports x86_64 and the installer would fetch the Intel build (S37)
[[ "$(uname -m)" == arm64 ]] || stop "this terminal reports $(uname -m), not arm64 (Rosetta?): open a native terminal"
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || stop "macOS $(sw_vers -productVersion): llmster needs macOS 14 or newer"
for app in "/Applications/LM Studio.app" "$HOME/Applications/LM Studio.app"; do
  [[ -d "$app" ]] && stop "the LM Studio desktop app is installed; lms would pair with it (S26, S36). Not touched"
done

save_state                       # how the Mac was found, once (.state/before.env)
source "$STATE"
if [[ "$LMS_HOME_EXISTED" == yes && ! -f "$STATE_DIR/ours" ]]; then
  stop "~/.lmstudio was already there before this script ran; it is left alone (remove it yourself or use it as is)"
fi
touch "$STATE_DIR/ours"

need=0
[[ -x "$LMS_HOME/llmster/$LLMSTER_VERSION/llmster" ]] || need=$((need + NEED_BUNDLE_GB))
has_model || need=$((need + NEED_MODEL_GB))
free="$(free_gb)"
(( need == 0 || free >= FLOOR_GB + need )) ||
  stop "$free GB free; this needs $need GB and keeps $FLOOR_GB GB free, so free up $((FLOOR_GB + need - free)) GB first"

# 2. llmster and lms, with the official installer (the version it installs is checked first)
if [[ -x "$LMS_HOME/llmster/$LLMSTER_VERSION/llmster" && -x "$LMS" ]]; then
  echo "llmster $LLMSTER_VERSION already installed"
else
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  limit 120 curl -fsSL "$INSTALLER_URL" -o "$tmp/install.sh" || stop "could not download $INSTALLER_URL"
  got="$(sed -n 's/^APP_VERSION="\(.*\)"$/\1/p' "$tmp/install.sh")"
  [[ "$got" == "$LLMSTER_VERSION" ]] ||
    stop "the installer now gives llmster '$got', not $LLMSTER_VERSION (tested): check the release notes, then update LLMSTER_VERSION in lib/state.sh"
  t0="$(now)"
  # the installer prints the home path twice; it is shown as ~
  limit 1200 sh "$tmp/install.sh" 2>&1 | mask || stop "the LM Studio installer failed"
  echo "installer: $(echo "$(now) - $t0" | bc) s"
fi
[[ -x "$LMS" ]] || stop "lms is not at ~/.lmstudio/bin/lms after the install"
(( $(path_block_count "$HOME/.zshrc") >= 1 )) || echo "note: no PATH block in ~/.zshrc; add: export PATH=\"\$HOME/.lmstudio/bin:\$PATH\""

# 3. The engine (in this session only: no login item, no launchd service)
limit 120 "$LMS" daemon up 2>&1 | mask || stop "lms daemon up failed"
daemon_running || stop "the llmster daemon did not start"

# 4. One small model (2.1 GB). The engine does the download (it carries on if lms is stopped, and a second
#    `lms get` joins it). lms redraws its progress bar ten times a second, so its output goes to .state/get.log and
#    this prints one line a minute. A download with no progress for 5 minutes, or over 2 hours, is retried once
#    (lms's downloader ran at 0.45-1 MB/s on 19 Nov 2026: 33-80 minutes for this model).
get_model() {
  local log="$STATE_DIR/get.log" pid last=-1 size same=0 i=0
  "$LMS" get "$MODEL" -y < /dev/null > "$log" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5; i=$((i + 5))
    (( i % 60 == 0 )) || continue
    size="$(find "$LMS_HOME/models" -name 'downloading_*.part' -exec stat -f %z {} \; 2>/dev/null | awk '{s += $1} END {printf "%d", s}')"
    echo "  downloading: $(echo "scale=2; $size / 1000000000" | bc) GB of $MODEL_GB GB ($((i / 60)) min)"
    if [[ "$size" == "$last" ]]; then same=$((same + 1)); else same=0; fi; last="$size"
    if (( same >= 5 )); then echo "  no progress for 5 minutes"; kill "$pid" 2>/dev/null; break; fi
    if (( i >= 7200 )); then echo "  still downloading after 2 hours"; kill "$pid" 2>/dev/null; break; fi
  done
  wait "$pid" 2>/dev/null
  has_model
}
if has_model; then
  echo "model $MODEL already downloaded"
else
  t0="$(now)"
  echo "downloading $MODEL ($MODEL_GB GB): lms get $MODEL -y"
  if ! get_model; then
    echo "the download stopped; restarting the daemon and trying once more"
    limit 60 "$LMS" daemon down >/dev/null 2>&1 || true
    find "$LMS_HOME/models" -name 'downloading_*.part' -delete 2>/dev/null || true
    limit 120 "$LMS" daemon up >/dev/null 2>&1 || stop "the llmster daemon did not restart"
    get_model || true
    has_model || stop "the model download failed twice"
  fi
  echo "model download: $(echo "$(now) - $t0" | bc) s"
fi

echo "installed: llmster $LLMSTER_VERSION, lms ($("$LMS" --version 2>/dev/null | tr -d '\n')), model $MODEL"
echo "In a new terminal lms is on your PATH. In this one, run: export PATH=\"\$HOME/.lmstudio/bin:\$PATH\""
