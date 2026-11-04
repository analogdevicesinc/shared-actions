#!/usr/bin/env bash
#
# Update debian/changelog from git commits, in place at CONTROL_PATH.
#
#   - If the top stanza is still a template (version @VERSION@), its entries are
#     regenerated in place.
#   - Otherwise (the top stanza is a real, released entry), a new template stanza
#     is prepended above the existing history.
#
# Version and date stay as @VERSION@/@DATE@ for deb-generator-action to fill at
# build time. This script does NOT commit, push, or open a PR — it only rewrites
# the changelog file. Inputs arrive as environment variables (set in action.yml).
set -euo pipefail

DISTRIBUTION="${DISTRIBUTION:-kuiper}"
LOG_FORMAT="  * %s"

cd "$WORKING_DIRECTORY"

CHANGELOG="$CONTROL_PATH/changelog"
CONTROL="$CONTROL_PATH/control"
for f in "$CHANGELOG" "$CONTROL"; do
    [ -f "$f" ] || { echo "::error::expected file not found at $WORKING_DIRECTORY/$f"; exit 1; }
done

emit() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"; return 0; }

# Package name and maintainer come straight from the debian control file.
PKG=$(sed -n 's/^Source:[[:space:]]*//p' "$CONTROL" | head -1)
MAINT=$(sed -n 's/^Maintainer:[[:space:]]*//p' "$CONTROL" | head -1)
if [ -z "$PKG" ] || [ -z "$MAINT" ]; then
    echo "::error::could not read Source:/Maintainer: from $CONTROL"
    exit 1
fi

# Commit range: SINCE..UNTIL.
#   UNTIL empty -> HEAD.
#   SINCE empty -> last reachable tag (whole history if there is none).
# Override either to widen (earlier SINCE) or shorten (earlier UNTIL) the range.
until_ref="${UNTIL:-HEAD}"
since_ref="$SINCE"
if [ -z "$since_ref" ]; then
    since_ref=$(git describe --tags --abbrev=0 "$until_ref" 2>/dev/null || true)
fi
range="${since_ref:+$since_ref..}$until_ref"
echo "Collecting commits for range: ${range}"

entries=$(git log "$range" --no-merges --pretty="$LOG_FORMAT")
count=$(printf '%s\n' "$entries" | grep -c . || true)
if [ "$count" -eq 0 ]; then
    echo "No commits in ${range}; changelog left unchanged."
    emit entries-count 0
    exit 0
fi
echo "Collected ${count} changelog entries."

# Build the new template stanza (version/date left to deb-generator).
new_stanza=$(printf '%s (@VERSION@) %s; urgency=low\n\n%s\n\n -- %s  @DATE@' \
    "$PKG" "$DISTRIBUTION" "$entries" "$MAINT")

if head -1 "$CHANGELOG" | grep -q '(@VERSION@)'; then
    # Top stanza is still a template -> overwrite it in place, keep the rest.
    trailer_ln=$(grep -n -m1 '^ -- ' "$CHANGELOG" | head -1 | cut -d: -f1 || true)
    [ -n "$trailer_ln" ] || { echo "::error::no ' -- ' trailer line in $CHANGELOG"; exit 1; }
    tail_content=$(tail -n +"$((trailer_ln + 1))" "$CHANGELOG")
    if [ -n "$tail_content" ]; then
        printf '%s\n%s\n' "$new_stanza" "$tail_content" > "$CHANGELOG"
    else
        printf '%s\n' "$new_stanza" > "$CHANGELOG"
    fi
    echo "Overwrote the template stanza in place."
else
    # Top stanza is a real release -> prepend a new template stanza above it.
    existing=$(cat "$CHANGELOG")
    printf '%s\n\n%s\n' "$new_stanza" "$existing" > "$CHANGELOG"
    echo "Prepended a new stanza above the existing history."
fi

emit entries-count "$count"
echo "Updated $CHANGELOG"
