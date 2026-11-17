#!/bin/bash
# Paperless-ngx 3.5.0 on a Mac: Colima (no Docker Desktop) + the Docker CLI + docker-compose, then three containers
# from compose.yaml (the web app, PostgreSQL 18, Valkey), reachable on http://localhost:8000 from this Mac only.
# Idempotent: run it again and it only does what is missing. Tested with Colima 0.10.3 and Paperless-ngx 3.5.0 on an
# Apple silicon Mac. Safe defaults: 127.0.0.1 only, pinned images, generated secrets and a generated admin password
# (in .env, readable by you only; never print it on screen), nothing set to start at login.
set -euo pipefail

PIN_COLIMA="${PIN_COLIMA:-0.10.3}"
PIN_DOCKER="${PIN_DOCKER:-29.9.3}"
PIN_COMPOSE="${PIN_COMPOSE:-5.7.1}"
CPUS="${CPUS:-4}"            # the same VM as the Colima episode: 4 CPUs,
MEMORY="${MEMORY:-8}"        # 8 GiB,
DISK="${DISK:-60}"           # 60 GiB disk
MIN_FREE_GB=8
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/state.sh"
DC=(docker-compose --project-directory "$HERE" -f "$HERE/compose.yaml")

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
    (( m >= 4 )) || fail "Colima is running with ${m} GiB; give it at least 4. Run 'colima stop', then 'colima start --cpus $CPUS --memory $MEMORY'"
    echo "colima already running ($c CPUs, $m GiB, $d GiB)" ;;
  *)
    s=$(date +%s)
    limit 1200 colima start --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" || fail "colima start failed or took over 20 min"
    echo "colima start: $(( $(date +%s) - s )) s" ;;
esac
[[ "$(docker context show)" == colima ]] || fail "the active Docker context is $(docker context show), not colima"
docker info --format '{{.ServerVersion}}' >/dev/null || fail "docker cannot reach the Colima engine"
vm_sees_here || fail "the Colima VM can't see this folder, so consume/ and export/ would stay inside the VM. Keep this folder in your home folder (Colima shares that), or start Colima with --mount \"\$HOME:w\" --mount \"$HERE:w\""

# 4. Secrets and the admin account, generated once into .env (only you can read it)
step "secrets"
if [[ -f "$HERE/.env" ]]; then
  echo ".env already there: kept"
else
  umask 077
  gen() { /usr/bin/python3 -c "import secrets; print(secrets.token_urlsafe($1))"; }
  {
    echo "# Made by install.sh. Secrets for this install only: don't share, don't print on screen."
    echo "SECRET_KEY=$(gen 48)"
    echo "DB_PASSWORD=$(gen 24)"
    echo "ADMIN_USER=paperless-admin"
    echo "ADMIN_PASSWORD=$(gen 18)"
  } > "$HERE/.env.tmp"
  mv "$HERE/.env.tmp" "$HERE/.env"
  umask 022
  echo ".env written (a new secret key, database password and admin password)"
fi
chmod 600 "$HERE/.env"
ADMIN_USER="$(sed -n 's/^ADMIN_USER=//p' "$HERE/.env")"

# 5. The folders shared with the containers
step "folders"
mkdir -p "$HERE/consume" "$HERE/export"

# 6. The images (about 1 GB to download) and the containers
step "pull"
have=yes; for i in "${IMAGES[@]}"; do docker image inspect "$i" >/dev/null 2>&1 || have=no; done
if [[ "$have" == yes ]]; then
  echo "images already here"
else
  s=$(date +%s)
  limit 1200 "${DC[@]}" pull --quiet || { echo "pull failed or stalled; trying once more"; limit 1200 "${DC[@]}" pull --quiet; } ||
    fail "docker-compose pull failed twice"
  echo "pull: $(( $(date +%s) - s )) s"
fi
step "up"
s=$(date +%s)
limit 300 "${DC[@]}" up -d || fail "docker-compose up failed"
cid() { "${DC[@]}" ps -q webserver; }
for _ in $(seq 1 120); do
  [[ "$(docker inspect "$(cid)" --format '{{.State.Health.Status}}' 2>/dev/null)" == healthy ]] && break
  sleep 3
done
[[ "$(docker inspect "$(cid)" --format '{{.State.Health.Status}}' 2>/dev/null)" == healthy ]] ||
  fail "the web app isn't healthy after 6 min (docker-compose logs webserver)"
echo "up to healthy: $(( $(date +%s) - s )) s"

# 7. The admin account (once). Made here, not with PAPERLESS_ADMIN_USER in compose.yaml, so a restore can go into
# an empty install (the document importer needs one).
step "admin"
pyq() { "${DC[@]}" exec -T --user paperless webserver python3 manage.py shell -c \
  "from django.contrib.auth.models import User; print($1)" 2>/dev/null | tail -1; }
admins="$(pyq "User.objects.filter(is_superuser=True).count()")"
[[ "$admins" =~ ^[0-9]+$ ]] || fail "could not read the users from Paperless"
if [[ "$(pyq "User.objects.filter(username='$ADMIN_USER', is_superuser=True).exists()")" == True ]]; then
  echo "admin user $ADMIN_USER already there"
elif (( admins > 0 )); then
  echo "note: this install already has $admins admin user(s) (restored from a backup?); no new one made"
else
  pw="$(sed -n 's/^ADMIN_PASSWORD=//p' "$HERE/.env")"
  # straight to manage.py as the paperless user: the image's createsuperuser wrapper reloads the container's own
  # environment and drops DJANGO_SUPERUSER_PASSWORD (pass 0: the user got no usable password)
  DJANGO_SUPERUSER_PASSWORD="$pw" "${DC[@]}" exec -T --user paperless -e DJANGO_SUPERUSER_PASSWORD webserver \
    python3 manage.py createsuperuser --noinput --username "$ADMIN_USER" --email "" >/dev/null 2>&1 ||
    fail "could not make the admin user"
  unset pw
  echo "admin user $ADMIN_USER made (its password is in .env)"
fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -K - http://127.0.0.1:8000/api/profile/ <<<"user = \"$ADMIN_USER:$(sed -n 's/^ADMIN_PASSWORD=//p' "$HERE/.env")\"")"
[[ "$code" == 200 ]] || fail "$ADMIN_USER can't sign in through the API with the password in .env (HTTP $code)"

step "done"
echo "installed: Paperless-ngx 3.5.0 on http://localhost:8000 (this Mac only); sign in as $ADMIN_USER"
