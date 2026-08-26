#!/bin/bash
# Copyright 2026 Analog Devices, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"
# Directory (relative to WORKING_DIRECTORY) holding the debian control files and
# templates (changelog, control, rules, ...).
CONTROL_PATH="${CONTROL_PATH:-packaging/debian}"

# Where built artifacts are collected. GITHUB_WORKSPACE is set in CI; fall back
# to the directory the script was invoked from (captured before any cd).
INVOCATION_DIR="$(pwd)"

# 1. Validate VERSION (non-empty and Debian-upstream-safe)
if [ -z "$VERSION" ]; then
  echo "ERROR: VERSION is required" >&2
  exit 1
fi
# Debian upstream versions start with a digit and use a limited charset.
# Reject anything else so it cannot corrupt the sed substitutions below.
if ! [[ "$VERSION" =~ ^[0-9][A-Za-z0-9.+~-]*$ ]]; then
  echo "ERROR: VERSION '$VERSION' is not a valid Debian upstream version" >&2
  echo "       (must start with a digit and contain only [A-Za-z0-9.+~-])" >&2
  exit 1
fi

# 2. Validate the working directory exists, then enter it
if [ ! -d "$WORKING_DIRECTORY" ]; then
  echo "ERROR: working directory not found: $WORKING_DIRECTORY" >&2
  exit 1
fi
cd "$WORKING_DIRECTORY"

# 3. Validate the control directory exists
if [ ! -d "$CONTROL_PATH" ]; then
  echo "ERROR: $CONTROL_PATH/ directory not found in $WORKING_DIRECTORY" >&2
  exit 1
fi

# 4. Read package name from the control file
APP_NAME=$(grep -m1 '^Source:' "$CONTROL_PATH/control" | awk '{print $2}')
if [ -z "$APP_NAME" ]; then
  echo "ERROR: Could not read Source: from $CONTROL_PATH/control" >&2
  exit 1
fi
echo "==> Package: $APP_NAME  Version: $VERSION"

# 5. Determine sudo
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# 6. Install sudo in containers where it's missing
if [ "$(id -u)" -eq 0 ] && ! command -v sudo &>/dev/null; then
  apt-get update -qq
  apt-get install -y -qq sudo
fi

# 7. Install base build deps
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq build-essential devscripts debhelper dpkg-dev equivs rsync

# 8. Add ADI package feed (packages.analog.com / Cloudsmith adi/external).
# This is Analog Devices' officially documented apt setup command; it installs
# a pinned keyring and a sources.list.d entry so packages such as libiio-dev
# resolve. Ref: https://packages.analog.com/public/setup.deb.sh
echo "==> Adding ADI package repository..."
# ${SUDO:+sudo -E} keeps sudo's -E (preserve-env) flag attached to sudo: it
# expands to "sudo -E" for a non-root user and to nothing for root (SUDO="",
# e.g. in a container), where a bare "-E" would be parsed as a command.
curl -1sLf 'https://packages.analog.com/public/setup.deb.sh' | ${SUDO:+sudo -E} bash
# Uncomment the line below to also add the adi/kuiper feed if packages
# are missing from adi/external (some may only be published to kuiper)
# curl -1sLf 'https://packages.analog.com/kuiper/setup.deb.sh' | ${SUDO:+sudo -E} bash
$SUDO apt-get update -qq

# 9. Assemble an isolated build tree so the caller's checked-out workspace is
# never mutated (packaging/ and .git in the source are left untouched).
build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT
src_dir="${build_root}/${APP_NAME}"
echo "==> Copying source to isolated build tree: $src_dir"

# rsync copies the source, excluding .git, the debian template dir, and any
# IGNORE_PATH entries. Using an array keeps paths with spaces/globs intact.
# The control path is anchored to the transfer root with a leading '/' so a
# single-component path (e.g. "debian") does not also match nested dirs.
rsync_excludes=(--exclude='.git' --exclude="/$CONTROL_PATH")
if [ -n "$IGNORE_PATH" ]; then
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    rsync_excludes+=(--exclude="$path")
  done <<< "$IGNORE_PATH"
fi
mkdir -p "$src_dir"
rsync -a "${rsync_excludes[@]}" ./ "$src_dir/"

# Place the debian template dir at debian/ in the build tree (it was excluded
# from the rsync above so it does not also appear under its original path).
cp -r "$CONTROL_PATH" "$src_dir/debian"

cd "$src_dir"

# 10. Process templates (sed only — the standard).
# VERSION is validated above and the '|' delimiter cannot appear in it, so the
# substitutions are safe.
echo "==> Processing templates..."
ARCHITECTURE=$(dpkg --print-architecture)
DATE_RFC="$(date -R)"
sed -i "s|@VERSION@|${VERSION}-1|" debian/changelog
sed -i "s|@DATE@|${DATE_RFC}|" debian/changelog
sed -i "s|@ARCHITECTURE@|${ARCHITECTURE}|" debian/control

# 11. Auto-install build dependencies from debian/control. Fail fast if they
# cannot be resolved, rather than letting debuild fail later with less context.
echo "==> Installing build dependencies from debian/control..."
$SUDO mk-build-deps --install --remove -t "$SUDO apt-get -y -qq --no-install-recommends" debian/control

# 12. Create orig tarball from the isolated tree (debian/ becomes the
# .debian.tar.xz; .git and IGNORE_PATH entries were already excluded by rsync).
echo "==> Creating orig tarball..."
pushd .. > /dev/null
tar czf "${APP_NAME}_${VERSION}.orig.tar.gz" --exclude=debian "$APP_NAME"
echo "    Created ${APP_NAME}_${VERSION}.orig.tar.gz"
popd > /dev/null

# 13. Build
echo "==> Building package..."
debuild -us -uc

# 14. Collect artifacts into the caller's workspace
echo "==> Collecting artifacts..."
artifact_dir="${GITHUB_WORKSPACE:-$INVOCATION_DIR}/artifacts"
mkdir -p "$artifact_dir"
cp -f ../*.deb "$artifact_dir/" 2>/dev/null || true
cp -f ../*.dsc ../*.debian.tar.xz ../*.orig.tar.gz "$artifact_dir/" 2>/dev/null || true
cp -f ../*.buildinfo ../*.changes "$artifact_dir/" 2>/dev/null || true
echo "==> Build complete: $APP_NAME $VERSION"
ls -la "$artifact_dir/" 2>/dev/null || true
