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

set -euo pipefail

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"
BASE_REF="${BASE_REF:-}"

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

CHANGED_FILES="$(git diff --name-only --diff-filter=d "${RANGE[@]}")"

DELIMITER="files_GHEOF_$$"
{
  echo "files<<${DELIMITER}"
  echo "${CHANGED_FILES}"
  echo "${DELIMITER}"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
