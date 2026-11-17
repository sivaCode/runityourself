# Shared by install.sh and uninstall.sh (sourced, not run).
# Saves how this Mac was found, once, under .state/ next to the scripts, so uninstall.sh can put it back.
HERE="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="$HERE/.state"
STATE="$STATE_DIR/before.env"
PROJECT=paperless
IMAGES=(ghcr.io/paperless-ngx/paperless-ngx:3.5.0 postgres:18 valkey/valkey:9-alpine)
VOLUMES=(paperless_data paperless_media paperless_pgdata paperless_redisdata)
FORMULAE=(colima lima docker docker-compose)
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

ver_of() { brew list --versions "$1" 2>/dev/null | awk '{print $2}' || true; }
limit() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' -- "$s" "$@"; }   # macOS has no `timeout`

# The default Colima VM: none | Stopped | Running (and its size, "cpus memGiB diskGiB")
vm_status() { command -v colima >/dev/null 2>&1 || { echo none; return 0; }
  local j; j="$(colima list --json 2>/dev/null | grep '"name":"default"' || true)"
  [[ -n "$j" ]] || { echo none; return 0; }
  /usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("status","Stopped"))' "$j"; }
vm_size() { local j; j="$(colima list --json 2>/dev/null | grep '"name":"default"' || true)"
  [[ -n "$j" ]] || return 0
  /usr/bin/python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["cpus"], d["memory"]//2**30, d["disk"]//2**30)' "$j"; }
engine_up() { [[ "$(vm_status)" == Running ]] && docker info >/dev/null 2>&1; }
# compose.yaml's ./consume and ./export only reach the Mac if the VM shares this folder (by default: the home folder)
vm_sees_here() { limit 60 colima ssh -- test -f "$HERE/compose.yaml" >/dev/null 2>&1; }

save_state() {
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE" ]] && return 0
  local f v vm i n
  vm="$(vm_status)"
  {
    for f in "${FORMULAE[@]}"; do
      v="$(ver_of "$f")"; [[ -n "$v" ]] || v=none
      echo "WAS_${f//-/_}=$v"
    done
    echo "WAS_VM=$vm"
    [[ "$vm" == none ]] || echo "WAS_VM_SIZE=\"$(vm_size)\""
    if [[ "$vm" == Running ]] && docker info >/dev/null 2>&1; then
      n=0
      for i in "${IMAGES[@]}"; do
        docker image inspect "$i" >/dev/null 2>&1 && echo "IMAGE_EXISTED_$n=yes" || echo "IMAGE_EXISTED_$n=no"; n=$((n + 1))
      done
      [[ -n "$(docker volume ls -q --filter label=com.docker.compose.project=$PROJECT)" ]] && echo "VOLUMES_EXISTED=yes" || echo "VOLUMES_EXISTED=no"
    else
      echo "IMAGE_EXISTED_0=unknown IMAGE_EXISTED_1=unknown IMAGE_EXISTED_2=unknown VOLUMES_EXISTED=unknown"
    fi
    [[ -f "$HERE/.env" ]] && echo "ENV_EXISTED=yes" || echo "ENV_EXISTED=no"
    [[ -d "$HOME/.colima" ]] && echo "COLIMA_DIR_EXISTED=yes" || echo "COLIMA_DIR_EXISTED=no"
    [[ -d "$HOME/.docker" ]] && echo "DOCKER_DIR_EXISTED=yes" || echo "DOCKER_DIR_EXISTED=no"
    [[ -f "$HOME/.docker/config.json" ]] && echo "DOCKER_CONFIG_EXISTED=yes" || echo "DOCKER_CONFIG_EXISTED=no"
    [[ -f "$HOME/.ssh/config" ]] && echo "SSH_CONFIG_EXISTED=yes" || echo "SSH_CONFIG_EXISTED=no"
    [[ -d "$HOME/Library/Caches/colima" ]] && echo "COLIMA_CACHE_EXISTED=yes" || echo "COLIMA_CACHE_EXISTED=no"
    [[ -d "$HOME/Library/Caches/lima" ]] && echo "LIMA_CACHE_EXISTED=yes" || echo "LIMA_CACHE_EXISTED=no"
  } > "$STATE.tmp"
  if [[ -d "$HOME/.colima" ]]; then
    (cd "$HOME/.colima" && find . -mindepth 1 -type d | sort) > "$STATE_DIR/colima-dirs.txt"
  fi
  [[ -f "$HOME/.docker/config.json" ]] && cp -p "$HOME/.docker/config.json" "$STATE_DIR/docker-config.json"
  [[ -f "$HOME/.ssh/config" ]] && shasum -a 256 "$HOME/.ssh/config" | awk '{print $1}' > "$STATE_DIR/ssh-config.sha256"
  mv "$STATE.tmp" "$STATE"
}
