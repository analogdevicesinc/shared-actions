#!/usr/bin/env bats
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
#
# Tests for upsert-comment.sh
#
# No network: a fake `curl` on PATH logs every request and returns canned
# GitHub API responses, so the create/update/self-heal/delete/noop paths are
# exercised deterministically. Needs bats and jq (both present on the runner).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../bin/upsert-comment.sh"
  WORKDIR="$(mktemp -d)"
  STUBDIR="${WORKDIR}/stub"
  mkdir -p "${STUBDIR}"
  OUTPUT="${WORKDIR}/github_output"
  CURL_LOG="${WORKDIR}/curl.log"      # one "METHOD URL" line per request
  CURL_DATA="${WORKDIR}/curl.data"    # each -d payload
  : > "${OUTPUT}"; : > "${CURL_LOG}"; : > "${CURL_DATA}"

  # Fake `curl`: parse method/url/data, log them, and emit the
  # "<body>\n<http_code>" shape the script expects from -w '\n%{http_code}'.
  # GET returns FAKE_COMMENTS on page 1 and FAKE_COMMENTS_P2 afterwards.
  cat > "${STUBDIR}/curl" <<'STUB'
#!/usr/bin/env bash
method=GET; url=""; data=""; prev=""
for a in "$@"; do
  case "${prev}" in
    -X) method="${a}" ;;
    -d) data="${a}" ;;
  esac
  prev="${a}"; url="${a}"
done
printf '%s %s\n' "${method}" "${url}" >> "${CURL_LOG}"
[ -n "${data}" ] && printf '%s\n' "${data}" >> "${CURL_DATA}"
page="$(sed -n 's/.*[?&]page=\([0-9]\{1,\}\).*/\1/p' <<< "${url}")"
case "${method}" in
  GET)    if [ "${page:-1}" = "1" ]; then body="${FAKE_COMMENTS:-[]}"; else body="${FAKE_COMMENTS_P2:-[]}"; fi; code=200 ;;
  POST)   body='{"id":999}'; code=201 ;;
  PATCH)  body='{}'; code=200 ;;
  DELETE) body=''; code=204 ;;
  *)      body=''; code=500 ;;
esac
printf '%s\n%s' "${body}" "${code}"
STUB
  chmod +x "${STUBDIR}/curl"
}

teardown() {
  [ -n "${WORKDIR}" ] && rm -rf "${WORKDIR}"
}

# Run the script under test with the fake curl and sane defaults. Per-test
# overrides come from the environment (MARKER, BODY, BODY_FILE, GH_TOKEN,
# FAIL_ON_ERROR, FAKE_COMMENTS, FAKE_COMMENTS_P2).
run_upsert() {
  run env \
    PATH="${STUBDIR}:${PATH}" \
    GITHUB_OUTPUT="${OUTPUT}" \
    CURL_LOG="${CURL_LOG}" \
    CURL_DATA="${CURL_DATA}" \
    MARKER="${MARKER:-test-marker}" \
    GH_TOKEN="${GH_TOKEN-x}" \
    REPO="${REPO:-o/r}" \
    PR_NUMBER="${PR_NUMBER-1}" \
    BODY="${BODY:-}" \
    BODY_FILE="${BODY_FILE:-}" \
    FAIL_ON_ERROR="${FAIL_ON_ERROR:-false}" \
    FAKE_COMMENTS="${FAKE_COMMENTS:-[]}" \
    FAKE_COMMENTS_P2="${FAKE_COMMENTS_P2:-[]}" \
    bash "${SCRIPT}"
}

MARKED_1='[{"id":111,"body":"<!-- pr-comment:test-marker -->\nold"}]'
MARKED_2='[{"id":111,"body":"<!-- pr-comment:test-marker -->\na"},{"id":222,"body":"<!-- pr-comment:test-marker -->\nb"},{"id":333,"body":"unrelated"}]'

@test "script exists and is executable" {
  [ -x "${SCRIPT}" ]
}

@test "has valid bash syntax" {
  run bash -n "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "creates a comment when none exists and body is non-empty" {
  FAKE_COMMENTS='[]' BODY='hello' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=created$' "${OUTPUT}"
  grep -q '^comment-id=999$' "${OUTPUT}"
  grep -q 'POST .*/issues/1/comments' "${CURL_LOG}"
}

@test "updates the existing marked comment in place" {
  FAKE_COMMENTS="${MARKED_1}" BODY='new' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=updated$' "${OUTPUT}"
  grep -q '^comment-id=111$' "${OUTPUT}"
  grep -q 'PATCH .*/issues/comments/111' "${CURL_LOG}"
}

@test "self-heals: updates the first marked comment and deletes duplicates" {
  FAKE_COMMENTS="${MARKED_2}" BODY='new' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=updated$' "${OUTPUT}"
  grep -q '^comment-id=111$' "${OUTPUT}"
  grep -q 'PATCH .*/issues/comments/111' "${CURL_LOG}"
  grep -q 'DELETE .*/issues/comments/222' "${CURL_LOG}"
  ! grep -q 'DELETE .*/issues/comments/111' "${CURL_LOG}"
  ! grep -q '/issues/comments/333' "${CURL_LOG}"
}

@test "deletes all marked comments when the body is empty" {
  FAKE_COMMENTS="${MARKED_2}" BODY='' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=deleted$' "${OUTPUT}"
  grep -q 'DELETE .*/issues/comments/111' "${CURL_LOG}"
  grep -q 'DELETE .*/issues/comments/222' "${CURL_LOG}"
}

@test "noop when nothing to post and no existing comment" {
  FAKE_COMMENTS='[]' BODY='' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=noop$' "${OUTPUT}"
  ! grep -qE '^(POST|PATCH|DELETE) ' "${CURL_LOG}"
}

@test "body-file wins over body and triggers a create" {
  echo 'from file' > "${WORKDIR}/body.md"
  FAKE_COMMENTS='[]' BODY='' BODY_FILE="${WORKDIR}/body.md" run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=created$' "${OUTPUT}"
}

@test "empty body-file removes the marked comment" {
  : > "${WORKDIR}/empty.md"
  FAKE_COMMENTS="${MARKED_1}" BODY_FILE="${WORKDIR}/empty.md" run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=deleted$' "${OUTPUT}"
  grep -q 'DELETE .*/issues/comments/111' "${CURL_LOG}"
}

@test "missing body-file is treated as empty" {
  FAKE_COMMENTS='[]' BODY_FILE="${WORKDIR}/nope.md" run_upsert
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"not found"* ]]
  grep -q '^result=noop$' "${OUTPUT}"
}

@test "prepends the hidden marker to the posted body" {
  FAKE_COMMENTS='[]' BODY='hello world' run_upsert
  [ "${status}" -eq 0 ]
  grep -q 'pr-comment:test-marker' "${CURL_DATA}"
}

@test "warns and noops on an error when fail-on-error is false" {
  GH_TOKEN='' FAKE_COMMENTS='[]' BODY='x' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=noop$' "${OUTPUT}"
  [[ "${output}" == *"::warning"* ]]
}

@test "fails hard on an error when fail-on-error is true" {
  GH_TOKEN='' FAIL_ON_ERROR='true' BODY='x' run_upsert
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error"* ]]
}

@test "paginates to find a marked comment beyond the first page" {
  page1="$(jq -nc '[range(100) | {id: (.+1000), body: "noise"}]')"
  FAKE_COMMENTS="${page1}" \
  FAKE_COMMENTS_P2="${MARKED_1}" \
  BODY='new' run_upsert
  [ "${status}" -eq 0 ]
  grep -q '^result=updated$' "${OUTPUT}"
  grep -q '^comment-id=111$' "${OUTPUT}"
  grep -q 'page=2' "${CURL_LOG}"
}
