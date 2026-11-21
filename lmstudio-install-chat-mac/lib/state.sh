# Shared by install.sh, verify.sh and uninstall.sh (sourced, not run).
# Pinned versions, the paths the LM Studio installer touches, and the record of how this Mac was found (.state/),
# saved once, before anything is installed, so uninstall.sh can put the Mac back from .state/ alone.
HERE="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="$HERE/.state"
STATE="$STATE_DIR/before.env"

LLMSTER_VERSION="0.1.1-2"               # APP_VERSION in https://lmstudio.ai/install.sh, read 19 Nov 2026
INSTALLER_URL="https://lmstudio.ai/install.sh"
MODEL="ibm/granite-4.1-3b"               # Apache 2.0; `lms get -y` picks the GGUF Q4_K_M build on this Mac
MODEL_GB="2.10"                          # granite-4.1-3b-Q4_K_M.gguf, 2,099,501,664 bytes
LMS_HOME="$HOME/.lmstudio"
LMS="$LMS_HOME/bin/lms"
POINTER="$HOME/.lmstudio-home-pointer"
CACHE_HOME="$HOME/.cache/lm-studio"      # the installer's other possible home (S02, S42)
PROFILES=(.zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .config/fish/config.fish)
WIFI_DEV="${WIFI_DEV:-en1}"
FLOOR_GB=20                              # free space the scripts always leave on the Mac
NEED_BUNDLE_GB=4                         # llmster 0.1.1-2 unpacked: 3.8 GB (my test runs)
NEED_MODEL_GB=3                          # the model: 2.1 GB, plus room for its .part file

limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }   # macOS has no `timeout`
now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
free_gb() { df -k "$HOME" | awk 'NR==2 {printf "%d", $4 * 1024 / 1e9}'; }
mask() { sed -l -e "s#$HOME#~#g"; }      # never print the home path (it holds the account name)

# The PATH block lms adds to a shell profile. Two forms seen on the test Mac:
#   llmster's installer (19 Nov 2026):  "\n# Added by LM Studio CLI tool (lms)\nexport PATH=\"$PATH:<home>/.lmstudio/bin\"\n"
#   the desktop app's lms (17 Nov 2026): "# Added by LM Studio CLI (lms)" … "# End of LM Studio CLI section"
path_block_count() { if [[ -f "$1" ]]; then grep -c -E '^# Added by LM Studio CLI( tool)? \(lms\)' "$1" || true; else echo 0; fi; }
# lms output read whole, then matched (grep -q in a pipe can end lms early: SIGPIPE + pipefail = a false "no")
has_model() { local j; j="$("$LMS" ls --json 2>/dev/null)" || return 1; [[ "$j" == *"\"$MODEL\""* ]]; }
daemon_running() { local s; s="$(limit 30 "$LMS" daemon status 2>&1)" || return 1; [[ "$s" == *[Rr]unning* && "$s" != *"not running"* ]]; }
strip_path_block() {   # remove the block(s) from file $1 in place, and the blank line the installer put before it
  /usr/bin/perl -0777 -i -pe '
    s{(\A|\n)\n?# Added by LM Studio CLI tool \(lms\)\nexport PATH="[^"\n]*\.lmstudio/bin[^"\n]*"(?:\n|\z)}{$1}g;
    s{(\A|\n)\n?# Added by LM Studio CLI \(lms\)\n.*?# End of LM Studio CLI section(?:\n|\z)}{$1}gs;' "$1"
}

lms_running() { pgrep -x llmster >/dev/null 2>&1 || pgrep -f "$LMS_HOME/" >/dev/null 2>&1; }

save_state() {
  mkdir -p "$STATE_DIR/profiles"; chmod 700 "$STATE_DIR"
  [[ -f "$STATE" ]] && return 0
  local f key
  {
    [[ -e "$LMS_HOME" ]]   && echo "LMS_HOME_EXISTED=yes" || echo "LMS_HOME_EXISTED=no"
    [[ -e "$POINTER" ]]    && echo "POINTER_EXISTED=yes"  || echo "POINTER_EXISTED=no"
    [[ -e "$CACHE_HOME" ]] && echo "CACHE_HOME_EXISTED=yes" || echo "CACHE_HOME_EXISTED=no"
    [[ -d "$HOME/.cache" ]] && echo "DOT_CACHE_EXISTED=yes" || echo "DOT_CACHE_EXISTED=no"
    for f in "${PROFILES[@]}"; do
      key="PROFILE_$(echo "$f" | tr -c 'A-Za-z0-9\n' '_')"
      if [[ -f "$HOME/$f" ]]; then
        echo "$key=$(shasum -a 256 "$HOME/$f" | awk '{print $1}')"
        cp -p "$HOME/$f" "$STATE_DIR/profiles/$(basename "$f")"
      else
        echo "$key=absent"
      fi
    done
    echo "LAUNCH_AGENTS=\"$(ls "$HOME/Library/LaunchAgents" 2>/dev/null | tr '\n' ' ')\""
    echo "WIFI_WAS=\"$(networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | awk '{print $NF}')\""
  } > "$STATE.tmp"
  chmod 600 "$STATE.tmp" "$STATE_DIR"/profiles/* 2>/dev/null || true
  mv "$STATE.tmp" "$STATE"
}
