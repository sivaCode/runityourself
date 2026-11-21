#!/bin/bash
# Check the LM Studio (llmster + lms) install. Every check is real: the files, a new shell's PATH, the running engine,
# the model on disk, a real answer from it, and what must NOT be there (an open network port, a login, a login item).
# Prints ALL CHECKS PASSED, or the first check that failed. Prints no home path, account or host name.
#   ./verify.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
n=0
ok()   { n=$((n + 1)); printf '%2d ok   %s\n' "$n" "$1"; }
fail() { n=$((n + 1)); printf '%2d FAIL %s\n' "$n" "$1"; exit 1; }

[[ "$(uname -m)" == arm64 ]] && ok "Apple Silicon (arm64), macOS $(sw_vers -productVersion)" || fail "not arm64"
[[ -x "$LMS_HOME/llmster/$LLMSTER_VERSION/llmster" ]] && ok "llmster $LLMSTER_VERSION installed" || fail "llmster $LLMSTER_VERSION missing"
v="$(limit 30 "$LMS" --version 2>/dev/null | tr -d '\n')"
[[ "$v" == *"CLI commit"* ]] && ok "lms CLI ($v)" || fail "lms doesn't run"
(( $(path_block_count "$HOME/.zshrc") == 1 )) && ok "one PATH block in ~/.zshrc" || fail "~/.zshrc has $(path_block_count "$HOME/.zshrc") LM Studio PATH blocks, not 1"
found="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TERM=xterm-256color zsh -i -c 'command -v lms' 2>/dev/null | tail -n 1)"
[[ "$found" == "$LMS" ]] && ok "a new terminal finds lms" || fail "a new zsh doesn't find lms on its PATH"

daemon_running && ok "the llmster engine is running" || fail "the engine isn't running (lms daemon up)"
has_model && ok "model $MODEL on disk" || fail "model $MODEL not downloaded (lms get $MODEL -y)"
[[ -z "$(find "$LMS_HOME/models" -name 'downloading_*.part' 2>/dev/null)" ]] && ok "no half-finished download" || fail "a half-finished download (.part) is in the models folder"

t0="$(now)"
answer="$(limit 300 "$LMS" chat "$MODEL" --dont-fetch-catalog -p "What is 17 plus 25? Reply with the number only." < /dev/null 2>/dev/null)"
t1="$(now)"
[[ "$answer" == *42* ]] && ok "a real answer: 17 + 25 = $(echo "$answer" | tr -d '\n' | grep -o '42' | head -n 1) ($(echo "$t1 - $t0" | bc) s, model loaded on demand)" ||
  fail "the model's answer to 17 + 25 wasn't 42: '$(echo "$answer" | tr '\n' ' ' | cut -c1-80)'"

# Nothing listens for other machines: every port the engine opened is bound to localhost
pids="$(pgrep -x llmster; pgrep -f "$LMS_HOME/")"
open="$(for p in $pids; do lsof -nP -a -p "$p" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}'; done | sort -u)"
wide="$(echo "$open" | grep -v -E '^(127\.0\.0\.1|\[::1\]|localhost):' | grep -v '^$' || true)"
[[ -z "$wide" ]] && ok "no port open to other machines ($(echo "$open" | grep -c . | tr -d ' ') on localhost only)" || fail "the engine listens beyond this Mac: $wide"

who="$(limit 30 "$LMS" whoami 2>&1 < /dev/null)"
[[ "$who" == *[Nn]ot* ]] && ok "no LM Studio account logged in" || fail "lms whoami shows a login"
agents="$(ls "$HOME/Library/LaunchAgents" 2>/dev/null | grep -i -E 'lmstudio|llmster|elementlabs' || true)"
[[ -z "$agents" ]] && ok "no login item or LaunchAgent" || fail "a LaunchAgent was added: $agents"

echo "ALL CHECKS PASSED"
