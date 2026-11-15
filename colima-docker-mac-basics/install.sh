#!/bin/bash
# Colima + the Docker CLI + docker-compose on a Mac (Homebrew), then a small demo app. Idempotent: run it again and
# it only does what is missing. Tested versions are listed in README.md.
# Safe defaults: the demo app is published on 127.0.0.1 only; nothing is set to start at login (no brew services).
set -euo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
CPUS="${CPUS:-4}"            # of 10 cores on the test Mac mini
MEMORY="${MEMORY:-8}"        # GiB, of 16
DISK="${DISK:-60}"           # GiB; can grow later, never shrink
MIN_FREE_GB=20
URL="http://127.0.0.1:8080/"
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_INSTALL_CLEANUP=1   # no self-update, no prompt

fail() { echo "INSTALL FAILED: $*" >&2; exit 1; }
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }   # macOS has no `timeout`
t0=$(date +%s); step() { echo "== $1 (+$(( $(date +%s) - t0 )) s)"; }

# 1. Requirements
step "requirements"
[[ "$(uname -s)" == Darwin ]] || fail "this guide is for macOS"
(( $(sw_vers -productVersion | cut -d. -f1) >= 13 )) || fail "Colima needs macOS 13 or newer"
command -v brew >/dev/null || fail "Homebrew not found (https://brew.sh)"
(( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB + 5 )) || fail "need $((MIN_FREE_GB + 5)) GB free"
[[ -d /Applications/Docker.app ]] && echo "note: Docker Desktop is also installed; Colima will become the active context"

# 2. How the Mac was found (written once; uninstall.sh puts it back)
save_state

# 3. The three tools (Lima comes with Colima)
step "brew install"
missing=()
for f in colima docker docker-compose; do brew list --formula "$f" >/dev/null 2>&1 || missing+=("$f"); done
if (( ${#missing[@]} )); then
  s=$(date +%s); limit 900 brew install "${missing[@]}" || fail "brew install ${missing[*]} failed or took over 15 min"
  echo "brew install ${missing[*]}: $(( $(date +%s) - s )) s"
fi
v_colima="$(colima version | awk '/^colima version/ {print $3}')"
v_docker="$(docker --version)"; [[ "$v_docker" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && v_docker="${BASH_REMATCH[1]}"
v_compose="$(docker-compose version --short)"
[[ "$v_colima" == "$PIN_COLIMA" ]]   || fail "colima $v_colima installed, $PIN_COLIMA expected (set PIN_COLIMA to accept)"
[[ "$v_docker" == "$PIN_DOCKER" ]]   || fail "docker $v_docker installed, $PIN_DOCKER expected (set PIN_DOCKER to accept)"
[[ "$v_compose" == "$PIN_COMPOSE" ]] || fail "docker-compose $v_compose installed, $PIN_COMPOSE expected (set PIN_COMPOSE to accept)"
echo "colima $v_colima, lima $(ver_of lima), docker $v_docker, docker-compose $v_compose"

# 4. The VM. Size is set at start; CPU and memory change only with a stop and start, disk only grows.
step "colima start"
if colima status >/dev/null 2>&1; then
  cur="$(colima list --json | /usr/bin/python3 -c 'import json,sys; d=json.loads(sys.stdin.readline()); print(d["cpus"], d["memory"]//2**30, d["disk"]//2**30)')"
  [[ "$cur" == "$CPUS $MEMORY $DISK" ]] || fail "Colima is running with cpus/memory/disk = $cur; run 'colima stop', then this script again"
  echo "colima already running ($cur)"
else
  s=$(date +%s)
  limit 1200 colima start --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" || fail "colima start failed or took over 20 min"
  echo "colima start: $(( $(date +%s) - s )) s"
fi
[[ "$(docker context show)" == colima ]] || fail "the active Docker context is $(docker context show), not colima"
docker info --format '{{.ServerVersion}}' >/dev/null || fail "docker cannot reach the Colima engine"

# 5. The demo app
step "docker-compose up"
s=$(date +%s)
limit 600 docker-compose -f "$HERE/compose.yaml" up -d || fail "docker-compose up failed or took over 10 min"
for _ in $(seq 1 30); do curl -fsS --max-time 2 "$URL" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS --max-time 5 "$URL" >/dev/null || fail "the demo app did not answer on $URL"
echo "docker-compose up: $(( $(date +%s) - s )) s"

step "done"
echo "installed (colima $v_colima: $CPUS CPUs, $MEMORY GiB, $DISK GiB; demo app on $URL)"
