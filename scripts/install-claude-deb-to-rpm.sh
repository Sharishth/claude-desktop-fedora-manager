#!/usr/bin/bash
#
# install-claude-deb-to-rpm.sh
#
# Installs or updates Claude Desktop on Fedora by converting the latest .deb
# from Anthropic's apt repository into an rpm with alien.
# Re-running at the same version performs a clean reinstall.
#
# Unofficial. Run the uninstall step BEFORE installing an official package.

set -euo pipefail

REPO_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
PKG_NAME="claude-desktop"
MARKER_DIR="/var/lib/claude-deb2rpm"
MARKER_FILE="$MARKER_DIR/installed"
LAUNCHER="/usr/bin/claude-desktop"

RUNTIME_DEPS=(
  nss atk at-spi2-atk cups-libs libdrm gtk3 alsa-lib
  libxkbcommon mesa-libgbm libnotify libsecret xdg-utils
)

SKIP_CURRENT=0
INSTALL_DEPS=1
KEEP_FILES=0
FORCE=0

log()  { printf '[claude] %s\n' "$*"; }
warn() { printf '[claude] WARNING: %s\n' "$*" >&2; }
die()  { printf '[claude] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install-claude-deb-to-rpm.sh [options]

  --skip-current   exit without changes if the latest version is installed
  --no-deps        skip the runtime library check
  --keep-files     keep the downloaded deb and converted rpm
  --force          proceed even if the installed claude-desktop does not
                   look like an alien conversion (not recommended)
  -h, --help       show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-current) SKIP_CURRENT=1 ;;
    --no-deps)      INSTALL_DEPS=0 ;;
    --keep-files)   KEEP_FILES=1 ;;
    --force)        FORCE=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || die "sudo not found and not running as root"
fi

# Interactive progress output only on a terminal. The GUI reads a pipe.
if [ -t 2 ]; then
  CURL_PROGRESS=(--progress-bar)
  RPM_MODE="-Uvh"
else
  CURL_PROGRESS=(-sS)
  RPM_MODE="-Uv"
fi

case "$(uname -m)" in
  x86_64)  DEB_ARCH="amd64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *)       die "unsupported architecture: $(uname -m). Repository publishes amd64 and arm64 only." ;;
esac

for tool in curl rpm awk sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

is_ours() {
  [ -f "$MARKER_FILE" ] && return 0
  rpm -qi "$PKG_NAME" 2>/dev/null | grep -qiE 'converted from a \.?deb package by alien'
}

if rpm -q "$PKG_NAME" >/dev/null 2>&1 && ! is_ours; then
  if [ "$FORCE" -eq 1 ]; then
    warn "installed $PKG_NAME does not look like an alien conversion, continuing because of --force"
  else
    die "installed $PKG_NAME does not look like an alien conversion. It may be an official package. Use --force to override."
  fi
fi

log "querying repository index for $DEB_ARCH"
PACKAGES="$(curl -fsSL "$REPO_BASE/dists/stable/main/binary-$DEB_ARCH/Packages")" \
  || die "could not fetch repository index. Check network access to downloads.claude.ai"

DEB_PATH="$(awk '/^Filename: pool\/main\/c\/claude-desktop\/claude-desktop_/ { print $2 }' <<<"$PACKAGES" \
  | sort -V | tail -n 1)"
[ -n "$DEB_PATH" ] || die "no claude-desktop package found in the repository index"

EXPECTED_SHA="$(awk -v f="$DEB_PATH" '
  /^Filename:/ { fn = $2 }
  /^SHA256:/   { sha = $2 }
  /^$/         { if (fn == f && !found) { print sha; found = 1 } fn = ""; sha = "" }
  END          { if (!found && fn == f) print sha }
' <<<"$PACKAGES")"
[ -n "$EXPECTED_SHA" ] || die "no SHA256 found in repository index for $DEB_PATH"

DEB_FILE="$(basename "$DEB_PATH")"
LATEST_VER="$(sed -E 's/^claude-desktop_(.+)_[^_]+\.deb$/\1/' <<<"$DEB_FILE")"
UPSTREAM_VER="${LATEST_VER%-*}"
INSTALLED_VER="$(rpm -q --queryformat '%{VERSION}' "$PKG_NAME" 2>/dev/null || true)"

log "latest available:    $LATEST_VER"
log "currently installed: ${INSTALLED_VER:-none}"

if [ "$SKIP_CURRENT" -eq 1 ] && [ "$INSTALLED_VER" = "$UPSTREAM_VER" ]; then
  log "already at the latest version, nothing to do"
  exit 0
fi

if ! command -v alien >/dev/null 2>&1; then
  log "alien not found, installing it"
  $SUDO dnf install -y alien
fi

WORKDIR="$(mktemp -d /var/tmp/claude-deb2rpm.XXXXXX)"
cleanup() {
  if [ "$KEEP_FILES" -eq 1 ]; then
    log "files kept in $WORKDIR"
  else
    $SUDO rm -rf -- "$WORKDIR"
  fi
}
trap cleanup EXIT

log "downloading $DEB_FILE"
curl -fL "${CURL_PROGRESS[@]}" -o "$WORKDIR/$DEB_FILE" "$REPO_BASE/$DEB_PATH"

log "verifying checksum"
printf '%s  %s\n' "$EXPECTED_SHA" "$WORKDIR/$DEB_FILE" | sha256sum -c --quiet \
  || die "checksum mismatch for $DEB_FILE"

log "converting to rpm"
( cd "$WORKDIR" && $SUDO alien -r "$DEB_FILE" >/dev/null )

RPM_FILE="$(find "$WORKDIR" -maxdepth 1 -name '*.rpm' -print -quit)"
[ -n "$RPM_FILE" ] || die "alien did not produce an rpm"
log "built $(basename "$RPM_FILE")"

log "installing"
$SUDO rpm "$RPM_MODE" --replacefiles --replacepkgs --nodeps --noscripts --notriggers "$RPM_FILE"

if [ "$INSTALL_DEPS" -eq 1 ]; then
  MISSING=()
  for pkg in "${RUNTIME_DEPS[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
  done
  if [ "${#MISSING[@]}" -gt 0 ]; then
    log "installing runtime libraries: ${MISSING[*]}"
    $SUDO dnf install -y --skip-unavailable "${MISSING[@]}"
  else
    log "runtime libraries already present"
  fi
fi

if [ ! -e "$LAUNCHER" ]; then
  TARGET="$(rpm -ql "$PKG_NAME" 2>/dev/null \
    | grep -E '/(claude-desktop|claude|Claude)$' \
    | grep -vx "$LAUNCHER" \
    | while IFS= read -r f; do [ -f "$f" ] && [ -x "$f" ] && printf '%s\n' "$f"; done \
    | head -n 1 || true)"
  if [ -n "$TARGET" ]; then
    [ -L "$LAUNCHER" ] && $SUDO rm -f -- "$LAUNCHER"
    $SUDO ln -s "$TARGET" "$LAUNCHER"
    log "created $LAUNCHER -> $TARGET"
  else
    warn "could not locate the application binary, $LAUNCHER not created"
  fi
fi

SANDBOX="$(rpm -ql "$PKG_NAME" 2>/dev/null | grep -m1 '/chrome-sandbox$' || true)"
if [ -n "$SANDBOX" ] && [ -e "$SANDBOX" ]; then
  log "setting sandbox permissions on $SANDBOX"
  $SUDO chown root:root "$SANDBOX"
  $SUDO chmod 4755 "$SANDBOX"
fi

if command -v restorecon >/dev/null 2>&1; then
  log "restoring SELinux contexts"
  { rpm -ql "$PKG_NAME" 2>/dev/null; printf '%s\n' "$LAUNCHER"; } \
    | $SUDO xargs -r -d '\n' restorecon -F >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  $SUDO update-desktop-database >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

$SUDO install -d -m 755 "$MARKER_DIR"
printf 'version=%s\nsource=%s/%s\nsha256=%s\ninstalled=%s\n' \
  "$LATEST_VER" "$REPO_BASE" "$DEB_PATH" "$EXPECTED_SHA" "$(date -Iseconds)" \
  | $SUDO tee "$MARKER_FILE" >/dev/null

DESKTOP_FILE="$(rpm -ql "$PKG_NAME" 2>/dev/null | grep -m1 '\.desktop$' || true)"
if [ -n "$DESKTOP_FILE" ] && [ -f "$DESKTOP_FILE" ]; then
  EXEC_BIN="$(awk -F= '/^Exec=/ { split($2, a, " "); print a[1]; exit }' "$DESKTOP_FILE")"
  if [ -n "$EXEC_BIN" ] && ! command -v "$EXEC_BIN" >/dev/null 2>&1; then
    warn "desktop entry points to $EXEC_BIN, which was not found. The app launcher entry may not work."
  fi
fi

command -v claude-desktop >/dev/null 2>&1 || warn "claude-desktop is not on PATH"

log "done. Installed version: $(rpm -q --queryformat '%{VERSION}' "$PKG_NAME" 2>/dev/null)"
