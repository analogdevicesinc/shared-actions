#!/usr/bin/env bash
# Copyright (c) 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Lists the files changed by a pull request and writes them to GITHUB_OUTPUT
# as the multi-line output "files".
#
# Environment:
#   BASE_SHA  Base commit of an explicit range. When set, the base branch is
#             never fetched.
#   HEAD_SHA  Head commit of the range (default: HEAD).
#   BASE_REF  Base branch of the pull request, used when BASE_SHA is empty.
#   IGNORE_TRIVIAL_CHANGES
#             When "true", drop files whose only changes are renames without
#             edits, mode changes, or whitespace/blank-line changes.

set -euo pipefail

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"
BASE_REF="${BASE_REF:-}"
IGNORE_TRIVIAL_CHANGES="${IGNORE_TRIVIAL_CHANGES:-false}"

if [[ -n "${BASE_SHA}" ]]; then
  if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
    git fetch --depth=1 origin "${BASE_SHA}"
  fi
  RANGE=("${BASE_SHA}" "${HEAD_SHA}")
else
  : "${BASE_REF:?BASE_REF or BASE_SHA must be set}"
  # Fetch the base branch only when it is not already part of the history.
  if ! git merge-base --is-ancestor "origin/${BASE_REF}" HEAD 2>/dev/null; then
    git fetch origin "${BASE_REF}"
  fi
  RANGE=("origin/${BASE_REF}...HEAD")
fi

if [[ "${IGNORE_TRIVIAL_CHANGES}" == "true" ]]; then
  # --numstat reports 0 added / 0 deleted lines for pure renames, mode-only
  # changes and (with -w) whitespace-only changes. With -z a rename is
  # "<added>\t<deleted>\t\0<old>\0<new>\0" and any other entry is
  # "<added>\t<deleted>\t<path>\0".
  CHANGED_FILES=""
  while IFS= read -r -d '' record; do
    IFS=$'\t' read -r added deleted path <<< "${record}"
    if [[ -z "${path}" ]]; then
      IFS= read -r -d '' _old
      IFS= read -r -d '' path
    fi
    [[ "${added}" == "0" && "${deleted}" == "0" ]] && continue
    CHANGED_FILES+="${path}"$'\n'
  done < <(git diff -z --numstat -M -w --ignore-blank-lines --diff-filter=d "${RANGE[@]}")
  CHANGED_FILES="${CHANGED_FILES%$'\n'}"
else
  CHANGED_FILES="$(git diff --name-only --diff-filter=d "${RANGE[@]}")"
fi

DELIMITER="files_GHEOF_$$"
{
  echo "files<<${DELIMITER}"
  echo "${CHANGED_FILES}"
  echo "${DELIMITER}"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
