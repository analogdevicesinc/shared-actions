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

# Upsert a single "marked" comment on a pull request conversation.
#
# Finds every comment carrying the hidden marker <!-- pr-comment:$MARKER -->,
# then:
#   - empty body  -> deletes all of them (cleanup once nothing to report)
#   - non-empty   -> updates the first, creates one if none, deletes any extras
#                    (self-heal back to a single comment)
#
# Environment (set by action.yml):
#   MARKER         required unique key
#   BODY           Markdown body (or empty)
#   BODY_FILE      path to a Markdown body file (wins over BODY when set)
#   PR_NUMBER      pull request number
#   REPO           owner/name
#   GH_TOKEN       token with pull-requests: write
#   FAIL_ON_ERROR  "true" to fail the step on API errors (default: warn + noop)

set -euo pipefail

API="${GITHUB_API_URL:-https://api.github.com}"
MARK="<!-- pr-comment:${MARKER:-} -->"

set_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  else
    printf 'output %s=%s\n' "$1" "$2"
  fi
}

# On error: fail hard only when asked; otherwise warn, emit a noop result, and
# succeed so comment posting never breaks the build (e.g. fork PRs get a
# read-only token and cannot comment).
fail() {
  if [ "${FAIL_ON_ERROR:-false}" = "true" ]; then
    echo "::error ::pr-comment: $*"
    exit 1
  fi
  echo "::warning ::pr-comment: $*"
  set_output "comment-id" ""
  set_output "result" "noop"
  exit 0
}

[ -n "${MARKER:-}" ] || fail "input 'marker' is required"
[ -n "${GH_TOKEN:-}" ] || fail "no token provided"
[ -n "${REPO:-}" ] || fail "no repository provided"
[ -n "${PR_NUMBER:-}" ] || fail "no pull-request number (not a PR context?)"
command -v curl > /dev/null || fail "curl not found on the runner"

# JSON helpers: jq when present, else python3 (self-hosted runners often lack
# jq). Each reads the JSON document on stdin.
if command -v jq > /dev/null; then
  json_marked_ids() { jq -r --arg m "$1" '.[]? | select(.body != null and (.body | contains($m))) | .id'; }
  json_length()     { jq 'length'; }
  json_id()         { jq -r '.id'; }
  json_body()       { jq -n --arg b "$1" '{body: $b}'; }
elif command -v python3 > /dev/null; then
  json_marked_ids() {
    python3 -c 'import json,sys
for c in json.load(sys.stdin) or []:
    if isinstance(c.get("body"), str) and sys.argv[1] in c["body"]: print(c["id"])' "$1"
  }
  json_length()     { python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
  json_id()         { python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
  json_body()       { python3 -c 'import json,sys; print(json.dumps({"body": sys.argv[1]}))' "$1"; }
else
  fail "neither jq nor python3 found on the runner"
fi

# Resolve the body: a set body-file wins; a missing file means "empty".
BODY_TEXT="${BODY:-}"
if [ -n "${BODY_FILE:-}" ]; then
  if [ -f "${BODY_FILE}" ]; then
    BODY_TEXT="$(cat "${BODY_FILE}")"
  else
    echo "pr-comment: body-file '${BODY_FILE}' not found; treating body as empty."
    BODY_TEXT=""
  fi
fi

# curl wrapper: emits "<response body>\n<http_code>". Uses -sS (not -f) so HTTP
# errors come back as a parseable status code rather than a curl failure; only
# network-level failures make curl exit non-zero.
api() {
  local method="$1" url="$2" data="${3:-}"
  local args=(-sS -X "$method"
    -H "Authorization: Bearer ${GH_TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: shared-actions-pr-comment"
    -w '\n%{http_code}')
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi
  curl "${args[@]}" "$url"
}

http_ok() { [ "$1" -ge 200 ] && [ "$1" -lt 300 ]; }

delete_comment() {
  local id="$1" resp code
  resp="$(api DELETE "${API}/repos/${REPO}/issues/comments/${id}")" \
    || fail "delete request failed"
  code="$(printf '%s' "$resp" | tail -n1)"
  http_ok "$code" || fail "delete comment ${id} returned HTTP ${code}"
}

# --- Collect existing marked comment IDs (paginated) -------------------------
ids=()
page=1
while [ "$page" -le 50 ]; do
  resp="$(api GET "${API}/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100&page=${page}")" \
    || fail "list comments request failed"
  code="$(printf '%s' "$resp" | tail -n1)"
  data="$(printf '%s' "$resp" | sed '$d')"
  http_ok "$code" || fail "list comments returned HTTP ${code}"

  # while-read, not mapfile: macOS runners ship bash 3.2.
  while IFS= read -r id; do
    if [ -n "$id" ]; then ids+=("$id"); fi
  done < <(printf '%s' "$data" | json_marked_ids "$MARK")

  count="$(printf '%s' "$data" | json_length)"
  [ "${count:-0}" -lt 100 ] && break
  page=$((page + 1))
done

# --- Empty body: ensure the comment is absent --------------------------------
if [ -z "${BODY_TEXT//[[:space:]]/}" ]; then
  if [ "${#ids[@]}" -eq 0 ]; then
    echo "pr-comment: nothing to post and no existing comment; noop."
    set_output "comment-id" ""
    set_output "result" "noop"
    exit 0
  fi
  for id in "${ids[@]}"; do
    delete_comment "$id"
    echo "pr-comment: removed comment ${id}."
  done
  set_output "comment-id" ""
  set_output "result" "deleted"
  exit 0
fi

# --- Non-empty body: upsert (and collapse duplicates) ------------------------
full_body="${MARK}"$'\n'"${BODY_TEXT}"
payload="$(json_body "$full_body")"

if [ "${#ids[@]}" -eq 0 ]; then
  resp="$(api POST "${API}/repos/${REPO}/issues/${PR_NUMBER}/comments" "$payload")" \
    || fail "create request failed"
  code="$(printf '%s' "$resp" | tail -n1)"
  data="$(printf '%s' "$resp" | sed '$d')"
  http_ok "$code" || fail "create comment returned HTTP ${code}"
  new_id="$(printf '%s' "$data" | json_id)"
  echo "pr-comment: created comment ${new_id}."
  set_output "comment-id" "$new_id"
  set_output "result" "created"
  exit 0
fi

primary="${ids[0]}"
resp="$(api PATCH "${API}/repos/${REPO}/issues/comments/${primary}" "$payload")" \
  || fail "update request failed"
code="$(printf '%s' "$resp" | tail -n1)"
http_ok "$code" || fail "update comment ${primary} returned HTTP ${code}"
echo "pr-comment: updated comment ${primary}."

# Collapse any leftover duplicates from a previous race.
if [ "${#ids[@]}" -gt 1 ]; then
  for id in "${ids[@]:1}"; do
    delete_comment "$id"
    echo "pr-comment: removed duplicate comment ${id}."
  done
fi

set_output "comment-id" "$primary"
set_output "result" "updated"
