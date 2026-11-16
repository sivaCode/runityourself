#!/bin/bash
# Stirling-PDF 3.3.0 on a Mac: Colima (no Docker Desktop) + the Docker CLI + docker-compose, then one container
# from compose.yaml, reachable on http://localhost:8080 from this Mac only. Idempotent: run it again and it only
# does what is missing. Tested with Colima 0.10.3 and Stirling-PDF 3.3.0 on an Apple silicon Mac.
# Safe defaults: 127.0.0.1 only, login and analytics off, pinned image, nothing set to start at login.
set -euo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
CPUS="${CPUS:-4}"            # the same VM as the Colima episode: 4 CPUs,
MEMORY="${MEMORY:-8}"        # 8 GiB (the container is capped at 4 GB),
DISK="${DISK:-60}"           # 60 GiB disk
MIN_FREE_GB=10
STATUS_URL="http://127.0.0.1:8080/api/v1/info/status"
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
DC=(docker-compose -f "$HERE/compose.yaml")

fail() { echo "INSTALL FAILED: $*" >&2; exit 1; }
t0=$(date +%s); step() { echo "== $1 (+$(( $(date +%s) - t0 )) s)"; }

# 1. Requirements
step "requirements"
[[ "$(uname -s)" == Darwin ]] || fail "this guide is for macOS"
(( $(sw_vers -productVersion | cut -d. -f1) >= 13 )) || fail "Colima needs macOS 13 or newer"
command -v brew >/dev/null || fail "Homebrew not found (https://brew.sh)"
(( $(df -g / | awk 'NR==2 {print $4}') >= MIN_FREE_GB )) || fail "need $MIN_FREE_GB GB free disk"
save_state

# 2. Colima, the Docker CLI and docker-compose (skipped if the Colima episode already installed them)
step "tools"
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
echo "colima $v_colima, docker $v_docker, docker-compose $v_compose"

# 3. The Colima VM (CPU and memory change only with a stop and start; the disk only grows)
step "colima"
case "$(vm_status)" in
  Running)
    read -r c m d <<<"$(vm_size)"
    (( m >= 6 )) || fail "Colima is running with ${m} GiB; Stirling-PDF needs 4 GB for itself. Run 'colima stop', then 'colima start --cpus $CPUS --memory $MEMORY'"
    echo "colima already running ($c CPUs, $m GiB, $d GiB)" ;;
  *)
    s=$(date +%s)
    limit 1200 colima start --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" || fail "colima start failed or took over 20 min"
    echo "colima start: $(( $(date +%s) - s )) s" ;;
esac
[[ "$(docker context show)" == colima ]] || fail "the active Docker context is $(docker context show), not colima"
docker info --format '{{.ServerVersion}}' >/dev/null || fail "docker cannot reach the Colima engine"
vm_sees_here || fail "the Colima VM can't see this folder, so your settings would stay inside the VM. Keep this folder in your home folder (Colima shares that), or start Colima with --mount \"\$HOME:w\" --mount \"$HERE:w\""

# 4. The data folders (bind-mounted, so settings and OCR languages survive a restart or an update)
step "folders"
mkdir -p "$DATA"/{configs,logs,customFiles,pipeline,storage,tessdata}

# 5. The image (about 1.1 GB to download) and the container
step "pull"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image already here"
else
  s=$(date +%s)
  limit 1200 "${DC[@]}" pull --quiet || { echo "pull failed or stalled; trying once more"; limit 1200 "${DC[@]}" pull --quiet; } ||
    fail "docker-compose pull failed twice (try the Docker Hub copy: stirlingtools/stirling-pdf:3.3.0)"
  echo "pull: $(( $(date +%s) - s )) s"
fi
step "up"
s=$(date +%s)
limit 300 "${DC[@]}" up -d || fail "docker-compose up failed"
for _ in $(seq 1 100); do
  curl -fsS --max-time 3 "$STATUS_URL" 2>/dev/null | grep -q '"UP"' && break
  sleep 3
done
st="$(curl -fsS --max-time 5 "$STATUS_URL" 2>/dev/null || true)"
grep -q '"UP"' <<<"$st" || fail "Stirling-PDF did not report UP on $STATUS_URL within 5 min (docker-compose logs stirling-pdf)"
echo "up to UP: $(( $(date +%s) - s )) s  $st"
for _ in $(seq 1 60); do
  [[ "$(docker inspect stirling-pdf --format '{{.State.Health.Status}}' 2>/dev/null)" == healthy ]] && break
  sleep 2
done
[[ "$(docker inspect stirling-pdf --format '{{.State.Health.Status}}')" == healthy ]] || fail "the container's health check isn't healthy after 2 min"
echo "up to healthy: $(( $(date +%s) - s )) s"

step "done"
echo "installed: Stirling-PDF on http://localhost:8080 (this Mac only; colima $v_colima, $CPUS CPUs, $MEMORY GiB)"
