#!/usr/bin/env bats
# Copyright (c) 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Tests for get-changed-files.sh

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/get-changed-files.sh"

# Create an "origin" repo with a main branch, clone it, and add a feature
# commit in the clone. Sets ORIGIN, CLONE, BASE (main tip) and HEAD_SHA.
setup_repos() {
  ROOT="$(mktemp -d)"
  ORIGIN="${ROOT}/origin"
  CLONE="${ROOT}/clone"
  git init -q -b main "${ORIGIN}"
  git -C "${ORIGIN}" config user.email "test@test.com"
  git -C "${ORIGIN}" config user.name "Test"
  echo a > "${ORIGIN}/a.py"
  echo gone > "${ORIGIN}/gone.py"
  git -C "${ORIGIN}" add .
  git -C "${ORIGIN}" commit -q -m base
  BASE="$(git -C "${ORIGIN}" rev-parse HEAD)"

  git clone -q "${ORIGIN}" "${CLONE}"
  git -C "${CLONE}" config user.email "test@test.com"
  git -C "${CLONE}" config user.name "Test"
  git -C "${CLONE}" checkout -q -b feature
  echo b > "${CLONE}/b.py"
  git -C "${CLONE}" rm -q gone.py
  git -C "${CLONE}" add .
  git -C "${CLONE}" commit -q -m feature
  HEAD_SHA="$(git -C "${CLONE}" rev-parse HEAD)"

  export GITHUB_OUTPUT="${ROOT}/output.txt"
  : > "${GITHUB_OUTPUT}"
}

teardown() {
  [[ -n "${ROOT:-}" ]] && rm -rf "${ROOT}"
}

# Print the file list written to GITHUB_OUTPUT (without the delimiters)
changed_files() {
  sed '1d;$d' "${GITHUB_OUTPUT}"
}

@test "base-sha/head-sha lists changed files and excludes deleted ones" {
  setup_repos
  cd "${CLONE}"
  # Make origin unreachable: the range mode must not need it
  git remote set-url origin /nonexistent
  BASE_SHA="${BASE}" HEAD_SHA="${HEAD_SHA}" run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "b.py" ]]
}

@test "head-sha defaults to HEAD" {
  setup_repos
  cd "${CLONE}"
  BASE_SHA="${BASE}" run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "b.py" ]]
}

@test "missing base-sha is fetched from origin" {
  setup_repos
  # Second commit on origin, so a depth-1 clone does not contain BASE
  git -C "${ORIGIN}" config uploadpack.allowReachableSHA1InWant true
  echo n > "${ORIGIN}/n.py"
  git -C "${ORIGIN}" add n.py
  git -C "${ORIGIN}" commit -q -m next
  rm -rf "${CLONE}"
  git clone -q --depth=1 "file://${ORIGIN}" "${CLONE}"
  cd "${CLONE}"
  run git cat-file -e "${BASE}^{commit}"
  [[ "${status}" -ne 0 ]]
  BASE_SHA="${BASE}" run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  git cat-file -e "${BASE}^{commit}"
  [[ "$(changed_files)" == "n.py" ]]
}

@test "base ref already in history is not fetched" {
  setup_repos
  cd "${CLONE}"
  # Breaking origin proves that no fetch happens
  git remote set-url origin /nonexistent
  BASE_REF=main run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "b.py" ]]
}

@test "base ref missing locally is fetched" {
  setup_repos
  cd "${CLONE}"
  git update-ref -d refs/remotes/origin/main
  BASE_REF=main run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "b.py" ]]
}

@test "fails without BASE_SHA or BASE_REF" {
  setup_repos
  cd "${CLONE}"
  run bash "${SCRIPT}"
  [[ "${status}" -ne 0 ]]
}

# ── ignore-trivial-changes ───────────────────────────────────────

# Add a commit on top of the feature commit with trivial and real changes
trivial_commit() {
  printf 'line one\nline two\n' > "${CLONE}/ws.py"
  printf 'x\ny\nz\n' > "${CLONE}/moved.py"
  printf 'p\nq\nr\ns\n' > "${CLONE}/edited.py"
  printf '#!/bin/sh\necho hi\n' > "${CLONE}/mode.sh"
  git -C "${CLONE}" add .
  git -C "${CLONE}" commit -q -m files
  BASE2="$(git -C "${CLONE}" rev-parse HEAD)"

  printf 'line  one\n\nline two \n' > "${CLONE}/ws.py"
  git -C "${CLONE}" mv moved.py renamed.py
  git -C "${CLONE}" mv edited.py renamed_edited.py
  printf 'p\nq\nr\nCHANGED\n' > "${CLONE}/renamed_edited.py"
  chmod +x "${CLONE}/mode.sh"
  git -C "${CLONE}" add -A
  git -C "${CLONE}" -c core.fileMode=true commit -q -m trivial
}

@test "ignore-trivial-changes=true drops renames, mode and whitespace changes" {
  setup_repos
  cd "${CLONE}"
  git config core.fileMode true
  trivial_commit
  BASE_SHA="${BASE2}" IGNORE_TRIVIAL_CHANGES=true run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "renamed_edited.py" ]]
}

@test "ignore-trivial-changes is off by default" {
  setup_repos
  cd "${CLONE}"
  git config core.fileMode true
  trivial_commit
  BASE_SHA="${BASE2}" run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == *"mode.sh"* ]]
  [[ "$(changed_files)" == *"renamed.py"* ]]
  [[ "$(changed_files)" == *"ws.py"* ]]
  [[ "$(changed_files)" == *"renamed_edited.py"* ]]
}

@test "ignore-trivial-changes keeps new files and real edits" {
  setup_repos
  cd "${CLONE}"
  BASE_SHA="${BASE}" IGNORE_TRIVIAL_CHANGES=true run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(changed_files)" == "b.py" ]]
}
