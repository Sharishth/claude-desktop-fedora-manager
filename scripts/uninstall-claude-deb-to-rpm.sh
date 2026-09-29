#!/usr/bin/bash
#
# uninstall-claude-deb-to-rpm.sh
#
# Removes the alien-converted Claude Desktop package and the leftovers rpm
# does not track. Refuses to touch an official package, and never deletes a
# path owned by any installed rpm.

set -euo pipefail

PKG_NAME="claude-desktop"
MARKER_DIR="/var/lib/claude-deb2rpm"
MARKER_FILE="$MARKER_DIR/installed"
LAUNCHER="/usr/bin/claude-desktop"

PURGE=0
ASSUME_YES=0
FORCE=0

log()  { printf '[claude] %s\n' "$*"; }
warn() { printf '[claude] WARNING: %s\n' "$*" >&2; }
die()  { printf '[claude] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: uninstall-claude-deb-to-rpm.sh [options]

  --purge      also delete user config, cache and app data
  -y, --yes    do not prompt
  --force      remove claude-desktop even if it does not look like an
               alien conversion (not recommended)
  -h, --help   show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --purge)   PURGE=1 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || die "sudo not found and not running as root"
fi

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local reply=""
  printf '[claude] %s [y/N] ' "$1"
  read -r reply || true
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

is_ours() {
  [ -f "$MARKER_FILE" ] && return 0
  rpm -qi "$PKG_NAME" 2>/dev/null | grep -qiE 'converted from a \.?deb package by alien'
}

safe_rm() {
  local p="${1%/}"
  case "$p" in
    ""|/|/usr|/opt|/etc|/var|/home|/usr/bin|/usr/lib|/usr/lib64|/usr/libexec|\
    /usr/share|/usr/share/icons|/usr/share/applications|/usr/share/doc)
      warn "refusing to remove protected path: ${p:-<empty>}"; return 0 ;;
  esac
  case "$(basename "$p")" in
    *claude*|*Claude*) ;;
    *) warn "refusing to remove path without claude in its name: $p"; return 0 ;;
  esac
  [ -e "$p" ] || [ -L "$p" ] || return 0
  if rpm -qf "$p" >/dev/null 2>&1; then
    log "skipping $p, owned by $(rpm -qf "$p" | head -n 1)"
    return 0
  fi
  log "removing $p"
  $SUDO rm -rf -- "$p"
}

# Resolve the invoking desktop user under sudo or pkexec.
if [ -n "${SUDO_USER:-}" ]; then
  TARGET_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
  TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
else
  TARGET_USER="$(id -un)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || die "could not resolve home directory for $TARGET_USER"

OWNED_PATHS=()

if rpm -q "$PKG_NAME" >/dev/null 2>&1; then
  VER="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$PKG_NAME")"
  log "found $PKG_NAME $VER"

  if ! is_ours; then
    if [ "$FORCE" -eq 1 ]; then
      warn "package does not look like an alien conversion, continuing because of --force"
    else
      die "installed $PKG_NAME does not look like an alien conversion. It may be an official package. Nothing was removed. Use --force to override."
    fi
  fi

  mapfile -t OWNED_PATHS < <(
    {
      rpm -ql "$PKG_NAME" 2>/dev/null \
        | grep -E '^(/opt|/usr/lib|/usr/lib64|/usr/libexec|/usr/share)/[^/]*[cC]laude[^/]*' \
        | sed -E 's#^(/[^/]+(/[^/]+)?/[^/]*[cC]laude[^/]*).*#\1#'
      rpm -ql "$PKG_NAME" 2>/dev/null | grep -E '/[^/]*[cC]laude[^/]*$'
    } | sort -u
  )

  if confirm "remove package $PKG_NAME $VER?"; then
    $SUDO rpm -e --nodeps --noscripts --notriggers "$PKG_NAME"
    log "package removed"
  else
    log "aborted, nothing removed"
    exit 0
  fi
else
  log "$PKG_NAME is not installed via rpm, cleaning leftovers only"
fi

for p in "${OWNED_PATHS[@]}"; do
  safe_rm "$p"
done

STRAY_PATHS=(
  "$LAUNCHER"
  /etc/apt/sources.list.d/claude-desktop.list
  /usr/share/keyrings/claude-desktop-archive-keyring.asc
  /usr/share/applications/claude-desktop.desktop
  /opt/claude-desktop
  /usr/lib/claude-desktop
  "$MARKER_DIR"
)
for p in "${STRAY_PATHS[@]}"; do
  safe_rm "$p"
done

while IFS= read -r -d '' icon; do
  safe_rm "$icon"
done < <(find /usr/share/icons /usr/share/pixmaps -name '*claude-desktop*' -print0 2>/dev/null || true)

if [ "$PURGE" -eq 1 ]; then
  USER_PATHS=(
    "$TARGET_HOME/.config/Claude"
    "$TARGET_HOME/.config/claude-desktop"
    "$TARGET_HOME/.local/share/Claude"
    "$TARGET_HOME/.local/share/claude-desktop"
    "$TARGET_HOME/.cache/Claude"
    "$TARGET_HOME/.cache/claude-desktop"
  )
  FOUND=()
  for p in "${USER_PATHS[@]}"; do
    [ -e "$p" ] && FOUND+=("$p")
  done
  if [ "${#FOUND[@]}" -gt 0 ]; then
    printf '[claude]   %s\n' "${FOUND[@]}"
    if confirm "delete the user data above for $TARGET_USER?"; then
      for p in "${FOUND[@]}"; do
        log "removing $p"
        rm -rf -- "$p"
      done
    fi
  else
    log "no user data found"
  fi
else
  log "user data kept"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  $SUDO update-desktop-database >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

if command -v claude-desktop >/dev/null 2>&1; then
  warn "claude-desktop is still on PATH at $(command -v claude-desktop)"
fi

log "done"
