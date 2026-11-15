# Shared by install.sh and uninstall.sh (sourced, not run).
# Saves how this Mac was found, once, under .state/ next to the scripts, so uninstall.sh can put it back.
HERE="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="$HERE/.state"
STATE="$STATE_DIR/before.env"
FORMULAE=(colima lima docker docker-compose)

ver_of() { brew list --versions "$1" 2>/dev/null | awk '{print $2}' || true; }

save_state() {
  mkdir -p "$STATE_DIR"
  [[ -f "$STATE" ]] && return 0
  local f v line=""
  {
    for f in "${FORMULAE[@]}"; do
      v="$(ver_of "$f")"; [[ -n "$v" ]] || v=none
      echo "WAS_${f//-/_}=$v"
    done
    [[ -d "$HOME/.colima" ]] && echo "COLIMA_DIR_EXISTED=yes" || echo "COLIMA_DIR_EXISTED=no"
    [[ -d "$HOME/.docker" ]] && echo "DOCKER_DIR_EXISTED=yes" || echo "DOCKER_DIR_EXISTED=no"
    [[ -f "$HOME/.docker/config.json" ]] && echo "DOCKER_CONFIG_EXISTED=yes" || echo "DOCKER_CONFIG_EXISTED=no"
    [[ -f "$HOME/.ssh/config" ]] && echo "SSH_CONFIG_EXISTED=yes" || echo "SSH_CONFIG_EXISTED=no"
    [[ -d "$HOME/Library/Caches/colima" ]] && echo "COLIMA_CACHE_EXISTED=yes" || echo "COLIMA_CACHE_EXISTED=no"
    [[ -d "$HOME/Library/Caches/lima" ]] && echo "LIMA_CACHE_EXISTED=yes" || echo "LIMA_CACHE_EXISTED=no"
  } > "$STATE.tmp"
  # The folders (only folders) that were in ~/.colima, so an empty skeleton can be put back as it was.
  if [[ -d "$HOME/.colima" ]]; then
    (cd "$HOME/.colima" && find . -mindepth 1 -type d | sort) > "$STATE_DIR/colima-dirs.txt"
  fi
  [[ -f "$HOME/.docker/config.json" ]] && cp -p "$HOME/.docker/config.json" "$STATE_DIR/docker-config.json"
  [[ -f "$HOME/.ssh/config" ]] && shasum -a 256 "$HOME/.ssh/config" | awk '{print $1}' > "$STATE_DIR/ssh-config.sha256"
  mv "$STATE.tmp" "$STATE"
}
