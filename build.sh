#!/usr/bin/bash
#
# Builds the claude-deb2rpm-manager rpm from a git checkout. Run on Fedora.
# Extra arguments are passed through to rpmbuild.
# Output: ./dist/*.rpm

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
NAME="claude-deb2rpm-manager"
VER="$(awk '/^Version:/ { print $2; exit }' "$NAME.spec")"

if ! command -v rpmbuild >/dev/null 2>&1 || ! command -v desktop-file-validate >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    dnf install -y rpm-build desktop-file-utils
  else
    sudo dnf install -y rpm-build desktop-file-utils
  fi
fi

TOP="$(mktemp -d)"
trap 'rm -rf -- "$TOP"' EXIT
mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

tar --exclude=./.git --exclude=./dist --transform "s,^\.,$NAME-$VER," \
  -czf "$TOP/SOURCES/$NAME-$VER.tar.gz" .

rpmbuild --define "_topdir $TOP" "$@" -ba "$NAME.spec"

mkdir -p dist
cp "$TOP"/RPMS/noarch/*.rpm "$TOP"/SRPMS/*.rpm dist/
ls -1 dist
