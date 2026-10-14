#!/usr/bin/env bash
# Copyright (c) 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────

log_info()     { echo "::notice::$*"; }
log_warn()     { echo "::warning::$*"; }
log_error()    { echo "::error::$*"; }
log_group()    { echo "::group::$1"; }
log_endgroup() { echo "::endgroup::"; }

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "${v}"
}

# ── Constants ────────────────────────────────────────────────────

CURRENT_YEAR="$(date +%Y)"

# ── Read & normalise inputs ──────────────────────────────────────

COPYRIGHT_PATTERN="${COPYRIGHT_PATTERN:?COPYRIGHT_PATTERN must be set}"
LICENSE_PATTERN="${LICENSE_PATTERN:-}"
LICENSE_HEADER_LINES="${INPUT_LICENSE_HEADER_LINES:-30}"
SCAN_PATH="${INPUT_SCAN_PATH:-.}"
SCAN_PATH="${SCAN_PATH#./}"
FAIL_ON_MISSING="${INPUT_FAIL_ON_MISSING:-true}"
SUMMARY_OUTPUT="${INPUT_SUMMARY_OUTPUT:-true}"
IGNORE_FILE="${INPUT_IGNORE_FILE:-.copyrightignore}"
FULL_SCAN="${INPUT_FULL_SCAN:-false}"
CHANGED_FILES="${CHANGED_FILES:-}"

# Parse valid-licenses from action input
VALID_LICENSES=()
if [[ -n "${INPUT_VALID_LICENSES:-}" ]]; then
  IFS=',' read -ra RAW_LICENSES <<< "${INPUT_VALID_LICENSES}"
  for lic in "${RAW_LICENSES[@]}"; do
    lic="$(trim "${lic}")"
    [[ -n "${lic}" ]] && VALID_LICENSES+=("${lic}")
  done
fi

# ── Detect repo license from LICENSE file ────────────────────────

DETECTED_LICENSE=""

detect_repo_license() {
  local license_file=""
  for candidate in LICENSE LICENSE.md LICENSE.txt COPYING COPYING.md; do
    if [[ -f "${candidate}" ]]; then
      license_file="${candidate}"
      break
    fi
  done

  if [[ -z "${license_file}" ]]; then
    log_info "No LICENSE file found in repository root."
    return
  fi

  # Try SPDX identifier in the file first (e.g. "SPDX-License-Identifier: BSD-3-Clause")
  local spdx_id
  spdx_id="$(grep -oP 'SPDX-License-Identifier:\s+\K\S+' "${license_file}" 2>/dev/null | head -n 1)" || true
  if [[ -n "${spdx_id}" ]]; then
    DETECTED_LICENSE="${spdx_id}"
    log_info "Detected repo license from ${license_file}: ${DETECTED_LICENSE} (via SPDX identifier)"
    return
  fi

  # Fall back to matching well-known license text patterns
  local content
  content="$(head -20 "${license_file}" 2>/dev/null)" || true

  if printf '%s' "${content}" | grep -qi "Apache License"; then
    if printf '%s' "${content}" | grep -q "Version 2.0"; then
      DETECTED_LICENSE="Apache-2.0"
    fi
  elif printf '%s' "${content}" | grep -qi "MIT License"; then
    DETECTED_LICENSE="MIT"
  elif printf '%s' "${content}" | grep -qi "GNU GENERAL PUBLIC LICENSE"; then
    if printf '%s' "${content}" | grep -q "Version 3"; then
      DETECTED_LICENSE="GPL-3.0-only"
    elif printf '%s' "${content}" | grep -q "Version 2"; then
      DETECTED_LICENSE="GPL-2.0-only"
    fi
  elif printf '%s' "${content}" | grep -qi "GNU LESSER GENERAL PUBLIC LICENSE"; then
    if printf '%s' "${content}" | grep -q "Version 2.1"; then
      DETECTED_LICENSE="LGPL-2.1-only"
    elif printf '%s' "${content}" | grep -q "Version 3"; then
      DETECTED_LICENSE="LGPL-3.0-only"
    fi
  elif printf '%s' "${content}" | grep -qi "BSD 3-Clause\|Redistribution and use in source and binary"; then
    DETECTED_LICENSE="BSD-3-Clause"
  elif printf '%s' "${content}" | grep -qi "BSD 2-Clause\|Simplified BSD"; then
    DETECTED_LICENSE="BSD-2-Clause"
  elif printf '%s' "${content}" | grep -qi "Mozilla Public License.*2\.0"; then
    DETECTED_LICENSE="MPL-2.0"
  elif printf '%s' "${content}" | grep -qi "ISC License"; then
    DETECTED_LICENSE="ISC"
  fi

  if [[ -n "${DETECTED_LICENSE}" ]]; then
    log_info "Detected repo license from ${license_file}: ${DETECTED_LICENSE} (via text matching)"
  else
    log_warn "Found ${license_file} but could not detect its SPDX identifier. Add 'SPDX-License-Identifier:' to the file or use .copyright-config.yml."
  fi
}

detect_repo_license

# ── Load .copyright-config.yml ──────────────────────────────────
# Simple YAML parser (no external dependencies). Supports:
#   project-license: Apache-2.0
#   allowed-licenses:
#     - MIT
#     - BSD-3-Clause  # vendored from project X

COPYRIGHT_CONFIG_FILE="${INPUT_COPYRIGHT_CONFIG:-".copyright-config.yml"}"
CONFIG_PROJECT_LICENSE=""
CONFIG_ALLOWED_LICENSES=()

load_copyright_config() {
  if [[ ! -f "${COPYRIGHT_CONFIG_FILE}" ]]; then
    return
  fi

  log_group "Loading config: ${COPYRIGHT_CONFIG_FILE}"

  local in_allowed_list=false
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # Strip inline comments and trailing whitespace
    local stripped="${line%%#*}"
    stripped="$(trim "${stripped}")"
    [[ -z "${stripped}" ]] && continue

    if [[ "${stripped}" =~ ^project-license:[[:space:]]*(.*) ]]; then
      CONFIG_PROJECT_LICENSE="$(trim "${BASH_REMATCH[1]}")"
      in_allowed_list=false
      echo "  project-license: ${CONFIG_PROJECT_LICENSE}"
    elif [[ "${stripped}" =~ ^allowed-licenses:[[:space:]]*$ ]]; then
      in_allowed_list=true
    elif [[ "${in_allowed_list}" == true && "${stripped}" =~ ^-[[:space:]]+(.*) ]]; then
      local val="$(trim "${BASH_REMATCH[1]}")"
      if [[ -n "${val}" ]]; then
        CONFIG_ALLOWED_LICENSES+=("${val}")
        echo "  allowed-license: ${val}"
      fi
    else
      in_allowed_list=false
    fi
  done < "${COPYRIGHT_CONFIG_FILE}"

  echo "Loaded config: project-license='${CONFIG_PROJECT_LICENSE}', ${#CONFIG_ALLOWED_LICENSES[@]} allowed license(s)."
  log_endgroup
}

load_copyright_config

# ── Merge license allowlist ──────────────────────────────────────
# Priority: .spdx-config.yml > action input > auto-detected repo license
# If .spdx-config.yml defines allowed-licenses, use those (+ project-license).
# Otherwise fall back to the valid-licenses action input.
# The detected repo license is always added to the allowlist if one is active.

build_license_allowlist() {
  # Start with config file if it defined an allowlist
  if (( ${#CONFIG_ALLOWED_LICENSES[@]} > 0 )); then
    VALID_LICENSES=("${CONFIG_ALLOWED_LICENSES[@]}")
  fi

  # Add project-license from config (if set)
  if [[ -n "${CONFIG_PROJECT_LICENSE}" ]]; then
    local already=false
    for lic in "${VALID_LICENSES[@]+"${VALID_LICENSES[@]}"}"; do
      [[ "${lic}" == "${CONFIG_PROJECT_LICENSE}" ]] && already=true && break
    done
    if [[ "${already}" == false ]]; then
      VALID_LICENSES+=("${CONFIG_PROJECT_LICENSE}")
    fi
  fi

  # Add detected repo license (if set and an allowlist is active)
  if [[ -n "${DETECTED_LICENSE}" ]] && (( ${#VALID_LICENSES[@]} > 0 )); then
    local already=false
    for lic in "${VALID_LICENSES[@]}"; do
      [[ "${lic}" == "${DETECTED_LICENSE}" ]] && already=true && break
    done
    if [[ "${already}" == false ]]; then
      VALID_LICENSES+=("${DETECTED_LICENSE}")
    fi
  fi
}

build_license_allowlist

# ── Build the ignore list ────────────────────────────────────────

IGNORED_FILES=()
IGNORE_PATTERNS=()

load_ignore_patterns() {
  if [[ ! -f "${IGNORE_FILE}" ]]; then
    log_info "No ignore file found at '${IGNORE_FILE}' — scanning all files."
    return
  fi

  log_group "Loading ignore file: ${IGNORE_FILE}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    IGNORE_PATTERNS+=("${line}")
    echo "  Ignore pattern: ${line}"
  done < "${IGNORE_FILE}"
  echo "Loaded ${#IGNORE_PATTERNS[@]} ignore pattern(s)."
  log_endgroup
}

load_ignore_patterns

# ── Gitignore-style pattern matching ─────────────────────────────
# Patterns are compiled once and cached in COMPILED_REGEXES / COMPILED_NEGATED
# so that is_ignored() never re-compiles.

compile_ignore_pattern() {
  local pattern="$1"
  local anchored=false basename_only=false directory_only=false
  local regex="" char="" length index

  pattern="${pattern#./}"

  [[ "${pattern}" == /* ]] && anchored=true && pattern="${pattern#/}"
  [[ "${pattern}" == */ ]] && directory_only=true && pattern="${pattern%/}"
  [[ "${anchored}" == false && "${pattern}" != */* ]] && basename_only=true

  length=${#pattern} index=0
  while (( index < length )); do
    char="${pattern:index:1}"

    if [[ "${char}" == '\\' ]] && (( index + 1 < length )); then
      index=$((index + 1)); char="${pattern:index:1}"
      # Escape regex metacharacters
      [[ "${char}" =~ [\\.\^\$\|\(\)\[\]\{\}\+\*\?] ]] && regex+='\\'
      regex+="${char}"
    elif [[ "${char}" == '*' ]]; then
      if [[ "${pattern:index:3}" == '**/' ]]; then
        regex+='(.*/)?'; index=$((index + 2))
      elif [[ "${pattern:index:2}" == '**' ]]; then
        regex+='.*'; index=$((index + 1))
      else
        regex+='[^/]*'
      fi
    elif [[ "${char}" == '?' ]]; then
      regex+='[^/]'
    else
      [[ "${char}" =~ [\\.\^\$\|\(\)\[\]\{\}\+] ]] && regex+='\\'
      regex+="${char}"
    fi
    index=$((index + 1))
  done

  [[ "${basename_only}" == true ]] && regex="(^|.*/)${regex}" || regex="^${regex}"
  [[ "${directory_only}" == true ]] && regex+="(/.*)?$" || regex+='$'

  printf '%s' "${regex}"
}

is_ignored() {
  local file="${1#./}" ignored=false
  local i

  for (( i = 0; i < ${#COMPILED_REGEXES[@]}; i++ )); do
    if [[ "${file}" =~ ${COMPILED_REGEXES[i]} ]]; then
      [[ "${COMPILED_NEGATED[i]}" == true ]] && ignored=false || ignored=true
    fi
  done
  [[ "${ignored}" == true ]]
}

# ── Pre-compile ignore patterns ──────────────────────────────────

COMPILED_REGEXES=()
COMPILED_NEGATED=()

for _pat in "${IGNORE_PATTERNS[@]+"${IGNORE_PATTERNS[@]}"}"; do
  _neg=false
  [[ "${_pat}" == \!* ]] && _neg=true && _pat="${_pat#!}"
  _pat="${_pat#./}"
  if [[ -n "${_pat}" ]]; then
    COMPILED_NEGATED+=("${_neg}")
    COMPILED_REGEXES+=("$(compile_ignore_pattern "${_pat}")")
  fi
done
unset _pat _neg

# ── File Discovery ───────────────────────────────────────────────

IFS=',' read -ra RAW_EXTS <<< "${INPUT_FILE_EXTENSIONS}"
EXT_ARRAY=()
for ext in "${RAW_EXTS[@]}"; do
  ext="$(trim "${ext}")"
  if [[ -n "${ext}" ]]; then
    if [[ ! "${ext}" =~ ^[A-Za-z0-9]+$ ]]; then
      log_error "Invalid file extension '${ext}'. Extensions must contain only alphanumeric characters."
      exit 1
    fi
    EXT_ARRAY+=("${ext}")
  fi
done

if (( ${#EXT_ARRAY[@]} == 0 )); then
  log_error "No file extensions configured. Set INPUT_FILE_EXTENSIONS to a comma-separated list (e.g. 'js,ts,py')."
  exit 1
fi

# Build extension regex for PR mode filtering
EXT_REGEX="\\.($(IFS='|'; echo "${EXT_ARRAY[*]}"))$"

# Build find name args: -name *.ext1 -o -name *.ext2 ...
FIND_NAME_ARGS=()
first=true
for ext in "${EXT_ARRAY[@]}"; do
  [[ -z "${ext}" ]] && continue
  [[ "${first}" == true ]] && first=false || FIND_NAME_ARGS+=("-o")
  FIND_NAME_ARGS+=("-name" "*.${ext}")
done

# Build find prune args for excluded directories
FIND_PRUNE_ARGS=()
declare -A SEEN_DIRS=()
first=true
IFS=',' read -ra EXCLUDE_ARRAY <<< "${INPUT_EXCLUDE_DIRS:-}"
for dir in node_modules dist build .git "${EXCLUDE_ARRAY[@]}"; do
  dir="$(trim "${dir}")"
  [[ -z "${dir}" || -n "${SEEN_DIRS[${dir}]:-}" ]] && continue
  SEEN_DIRS["${dir}"]=1
  [[ "${first}" == true ]] && first=false || FIND_PRUNE_ARGS+=("-o")
  FIND_PRUNE_ARGS+=("-name" "${dir}")
done

# ── Discover & filter files ──────────────────────────────────────

discover_and_filter_files() {
  log_group "Discovering source files"

  if [[ "${FULL_SCAN}" == "true" ]]; then
    log_info "Full scan mode enabled"
    mapfile -t ALL_FILES < <(find "${SCAN_PATH}" \( "${FIND_PRUNE_ARGS[@]}" \) -prune -o -type f \( "${FIND_NAME_ARGS[@]}" \) -print 2>/dev/null | sort)
  elif [[ -n "${CHANGED_FILES}" ]]; then
    log_info "Scanning only changed files"
    SCAN_FILTER="${EXT_REGEX}"
    if [[ "${SCAN_PATH}" != "." ]]; then
      ESCAPED_PATH=$(printf '%s' "${SCAN_PATH%/}" | sed 's/[.[\*^$+?(){}|\\]/\\&/g')
      SCAN_FILTER="^${ESCAPED_PATH}/.*${EXT_REGEX}"
    fi
    EXCLUDE_REGEX=""
    for dir in "${!SEEN_DIRS[@]}"; do
      [[ -n "${EXCLUDE_REGEX}" ]] && EXCLUDE_REGEX+="|"
      EXCLUDE_REGEX+="(^|/)$(printf '%s' "${dir}" | sed 's/[.[\*^$+?(){}|\\]/\\&/g')/"
    done
    if [[ -n "${EXCLUDE_REGEX}" ]]; then
      mapfile -t ALL_FILES < <(printf '%s\n' "${CHANGED_FILES}" | sed 's|^\./||' | grep -E "${SCAN_FILTER}" | grep -Ev "${EXCLUDE_REGEX}" || true)
    else
      mapfile -t ALL_FILES < <(printf '%s\n' "${CHANGED_FILES}" | sed 's|^\./||' | grep -E "${SCAN_FILTER}" || true)
    fi
  else
    log_info "No changed files to scan"
    ALL_FILES=()
  fi

  echo "Files discovered (before ignore filter):"
  printf '%s\n' "${ALL_FILES[@]+"${ALL_FILES[@]}"}"

  SOURCE_FILES=()
  IGNORED_COUNT=0
  for file in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
    if is_ignored "${file}"; then
      IGNORED_FILES+=("${file}")
      IGNORED_COUNT=$((IGNORED_COUNT + 1))
    else
      SOURCE_FILES+=("${file}")
    fi
  done

  echo "Files to scan (after ignore filter):"
  printf '%s\n' "${SOURCE_FILES[@]+"${SOURCE_FILES[@]}"}"

  TOTAL_SCANNED="${#SOURCE_FILES[@]}"
  echo "Found ${#ALL_FILES[@]} source file(s) total."
  echo "Ignored ${IGNORED_COUNT} file(s) via ${IGNORE_FILE}."
  echo "Found ${TOTAL_SCANNED} source file(s) to scan."
  log_endgroup
}

discover_and_filter_files

# ── Git history helpers ──────────────────────────────────────────

git_year() {
  local file="$1" flags="$2" pick="$3" result=""
  if result=$(git log ${flags} --format='%ad' --date=format:'%Y' -- "${file}" 2>/dev/null) && [[ -n "${result}" ]]; then
    if [[ "${pick}" == "last" ]]; then
      result="${result##*$'\n'}"
    else
      result="${result%%$'\n'*}"
    fi
    [[ "${result}" =~ ^[0-9]{4}$ ]] && printf '%s\n' "${result}"
  fi
}

# Determine the year the scanned file's current path first came into existence
# as a distinct file. Walk `git log --follow --name-status` from newest to
# oldest and use the year of the most recent commit whose status for the tracked
# path is an Add (A) or Copy (C). A rename (R) is a continuation of the same
# file, so keep following through it. A copy (C) creates a new, independent file,
# so the copy commit is the creation point.
git_first_year() {
  local file="${1#./}" line year="" creation="" tracked="${1#./}"
  local status path1 path2 code

  while IFS= read -r line; do
    if [[ "${line}" == "commit "* ]]; then
      year="${line#commit }"
      continue
    fi

    [[ -z "${line}" ]] && continue

    status=""; path1=""; path2=""
    IFS=$'\t' read -r status path1 path2 <<<"${line}"
    code="${status%%[0-9]*}"

    if [[ "${code}" == "A" && "${path1}" == "${tracked}" ]]; then
      [[ "${year}" =~ ^[0-9]{4}$ ]] && creation="${year}"
      break
    elif [[ "${code}" == "C" && "${path2}" == "${tracked}" ]]; then
      [[ "${year}" =~ ^[0-9]{4}$ ]] && creation="${year}"
      break
    elif [[ "${code}" == "R" && "${path2}" == "${tracked}" && -n "${path1}" ]]; then
      tracked="${path1}"
    fi
  done < <(git log --follow --name-status --format='commit %ad' --date=format:'%Y' -- "${file}" 2>/dev/null)

  if [[ -n "${creation}" ]]; then
    printf '%s\n' "${creation}"
  fi
  return 0
}

git_last_year()  { git_year "$1" "-1" "first"; }

# ── Copyright Validation ─────────────────────────────────────────

validate_file_copyright() {
  local file="$1"
  VALIDATION_DETAIL=""

  local COPYRIGHT_LINE
  COPYRIGHT_LINE="$(grep -oPi "${COPYRIGHT_PATTERN}" -- "${file}" 2>/dev/null | head -n 1)" || true

  if [[ -z "${COPYRIGHT_LINE}" ]]; then
    return 1  # Missing copyright
  fi

  # Extract year range from the matched line
  # Supports: "2026", "2020-2026", "2020 - 2026", "2020, 2026"
  local HEADER_START HEADER_END
  if [[ "${COPYRIGHT_LINE}" =~ ([0-9]{4})[[:space:]]*[-,][[:space:]]*([0-9]{4}) ]]; then
    HEADER_START="${BASH_REMATCH[1]}"
    HEADER_END="${BASH_REMATCH[2]}"
  elif [[ "${COPYRIGHT_LINE}" =~ ([0-9]{4}) ]]; then
    HEADER_START="${BASH_REMATCH[1]}"
    HEADER_END="${HEADER_START}"
  else
    return 2
  fi

  local GIT_FIRST="$(git_first_year "${file}")"
  local GIT_LAST="$(git_last_year "${file}")"
  [[ -z "${GIT_FIRST}" ]] && GIT_FIRST="${CURRENT_YEAR}"
  [[ -z "${GIT_LAST}" ]] && GIT_LAST="${CURRENT_YEAR}"

  local YEAR_OK=true

  if [[ "${HEADER_START}" != "${GIT_FIRST}" ]]; then
    YEAR_OK=false
    VALIDATION_DETAIL="Start year: header=${HEADER_START} git=${GIT_FIRST}"
  fi

  if [[ "${HEADER_END}" != "${GIT_LAST}" ]]; then
    YEAR_OK=false
    [[ -n "${VALIDATION_DETAIL}" ]] && VALIDATION_DETAIL+=", "
    VALIDATION_DETAIL+="End year: header=${HEADER_END} git=${GIT_LAST}"
  fi

  if [[ "${GIT_FIRST}" == "${GIT_LAST}" && "${HEADER_START}" != "${HEADER_END}" ]]; then
    YEAR_OK=false
    VALIDATION_DETAIL="File created and last modified in ${GIT_FIRST}, but header has range ${HEADER_START}-${HEADER_END}"
  fi

  [[ "${YEAR_OK}" == true ]] && return 0 || return 2  # Wrong years
}

# ── License Validation ───────────────────────────────────────────

LICENSE_VALIDATION_DETAIL=""

validate_file_license() {
  local file="$1"
  LICENSE_VALIDATION_DETAIL=""

  local license_line
  license_line="$(head -n "${LICENSE_HEADER_LINES}" -- "${file}" 2>/dev/null | grep -oPi "${LICENSE_PATTERN}" | head -n 1)" || true

  if [[ -z "${license_line}" ]]; then
    return 1  # Missing license
  fi

  # If valid-licenses list is configured, check the identifier is allowed
  if (( ${#VALID_LICENSES[@]} > 0 )); then
    local identifier
    identifier="$(printf '%s' "${license_line}" | grep -oP '(?<=SPDX-License-Identifier:\s)\S+')" || true

    if [[ -z "${identifier}" ]]; then
      LICENSE_VALIDATION_DETAIL="Could not extract license identifier from: ${license_line}"
      return 2
    fi

    local valid=false
    for lic in "${VALID_LICENSES[@]}"; do
      if [[ "${identifier}" == "${lic}" ]]; then
        valid=true
        break
      fi
    done
    if [[ "${valid}" == false ]]; then
      LICENSE_VALIDATION_DETAIL="License '${identifier}' not in valid-licenses list"
      return 2  # Invalid license
    fi
  fi

  return 0
}

# ── Scan files ───────────────────────────────────────────────────

log_group "Scanning for copyright/license headers"
echo "Copyright pattern: ${COPYRIGHT_PATTERN}"
if [[ -n "${LICENSE_PATTERN}" ]]; then
  echo "License pattern:   ${LICENSE_PATTERN}"
  if (( ${#VALID_LICENSES[@]} > 0 )); then
    echo "Allowed licenses:  ${VALID_LICENSES[*]}"
  fi
else
  echo "License check:     disabled"
fi
if [[ -n "${DETECTED_LICENSE}" ]]; then
  echo "Repo license:      ${DETECTED_LICENSE}"
fi
echo ""

MISSING_FILES=()
WRONG_YEAR_DETAILS=()
MISSING_LICENSE_FILES=()
INVALID_LICENSE_DETAILS=()
PASSED_FILES=0

for file in "${SOURCE_FILES[@]+"${SOURCE_FILES[@]}"}"; do
  file_has_error=false

  # Check copyright
  copyright_result=0
  validate_file_copyright "${file}" || copyright_result=$?

  case ${copyright_result} in
    1) MISSING_FILES+=("${file}")
       log_warn "Missing copyright header: ${file}"
       file_has_error=true ;;
    2) WRONG_YEAR_DETAILS+=("${file} → ${VALIDATION_DETAIL}")
       log_warn "Wrong copyright years: ${file} (${VALIDATION_DETAIL})"
       file_has_error=true ;;
  esac

  # Check license (only if license-pattern is configured)
  if [[ -n "${LICENSE_PATTERN}" ]]; then
    license_result=0
    validate_file_license "${file}" || license_result=$?

    case ${license_result} in
      1) MISSING_LICENSE_FILES+=("${file}")
         log_warn "Missing SPDX-License-Identifier: ${file}"
         file_has_error=true ;;
      2) INVALID_LICENSE_DETAILS+=("${file} → ${LICENSE_VALIDATION_DETAIL}")
         log_warn "Invalid license: ${file} (${LICENSE_VALIDATION_DETAIL})"
         file_has_error=true ;;
    esac
  fi

  if [[ "${file_has_error}" == false ]]; then
    PASSED_FILES=$((PASSED_FILES + 1))
  fi
done

MISSING_COUNT="${#MISSING_FILES[@]}"
WRONG_YEARS_COUNT="${#WRONG_YEAR_DETAILS[@]}"
MISSING_LICENSE_COUNT="${#MISSING_LICENSE_FILES[@]}"
INVALID_LICENSE_COUNT="${#INVALID_LICENSE_DETAILS[@]}"
TOTAL_ERRORS=$(( MISSING_COUNT + WRONG_YEARS_COUNT + MISSING_LICENSE_COUNT + INVALID_LICENSE_COUNT ))

echo ""
echo "Passed                        : ${PASSED_FILES}"
echo "Missing copyright header     : ${MISSING_COUNT}"
echo "Wrong copyright years         : ${WRONG_YEARS_COUNT}"
if [[ -n "${LICENSE_PATTERN}" ]]; then
  echo "Missing SPDX-License-Identifier: ${MISSING_LICENSE_COUNT}"
  echo "Invalid license identifier    : ${INVALID_LICENSE_COUNT}"
fi
echo "Ignored                       : ${IGNORED_COUNT}"

log_endgroup

# ── GitHub Actions outputs ───────────────────────────────────────

write_multiline() {
  local name="$1"; shift
  local delim="${name}_GHEOF_$$"
  echo "${name}<<${delim}"
  (( $# > 0 )) && printf '%s\n' "$@"
  echo "${delim}"
}

{
  echo "total_scanned=${TOTAL_SCANNED}"
  echo "missing_count=${MISSING_COUNT}"
  echo "wrong_years_count=${WRONG_YEARS_COUNT}"
  echo "missing_license_count=${MISSING_LICENSE_COUNT}"
  echo "invalid_license_count=${INVALID_LICENSE_COUNT}"
  echo "ignored_count=${IGNORED_COUNT}"
  echo "detected_license=${DETECTED_LICENSE}"
  echo "passed=$([ "${TOTAL_ERRORS}" -eq 0 ] && echo true || echo false)"
  write_multiline missing_files          "${MISSING_FILES[@]+"${MISSING_FILES[@]}"}"
  write_multiline wrong_years_files      "${WRONG_YEAR_DETAILS[@]+"${WRONG_YEAR_DETAILS[@]}"}"
  write_multiline missing_license_files  "${MISSING_LICENSE_FILES[@]+"${MISSING_LICENSE_FILES[@]}"}"
  write_multiline invalid_license_files  "${INVALID_LICENSE_DETAILS[@]+"${INVALID_LICENSE_DETAILS[@]}"}"
  write_multiline ignored_files          "${IGNORED_FILES[@]+"${IGNORED_FILES[@]}"}"
} >> "${GITHUB_OUTPUT}"

# ── Job Summary ──────────────────────────────────────────────────

summary_details_list() {
  local title="$1"; shift
  (( $# == 0 )) && return
  echo "<details>"
  echo "<summary>${title} ($#)</summary>"
  echo ""
  echo '```'
  printf '%s\n' "$@"
  echo '```'
  echo ""
  echo "</details>"
  echo ""
}

summary_details_table() {
  local title="$1"; shift
  (( $# == 0 )) && return
  echo "<details>"
  echo "<summary>${title} ($#)</summary>"
  echo ""
  echo "| File | Issue |"
  echo "|------|-------|"
  for detail in "$@"; do
    echo "| \`${detail%% →*}\` | ${detail#*→ } |"
  done
  echo ""
  echo "</details>"
  echo ""
}

if [[ "${SUMMARY_OUTPUT}" == "true" ]]; then
  {
    echo "## Copyright & License Check Results"
    echo ""
    if [[ -n "${DETECTED_LICENSE}" ]]; then
      echo "> **Repo license**: \`${DETECTED_LICENSE}\` (auto-detected from LICENSE file)"
      echo ""
    fi
    if (( ${#VALID_LICENSES[@]} > 0 )); then
      echo "> **Allowed licenses**: $(printf '\`%s\` ' "${VALID_LICENSES[@]}")"
      echo ""
    fi
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Total files scanned | **${TOTAL_SCANNED}** |"
    echo "| Ignored (via \`${IGNORE_FILE}\`) | **${IGNORED_COUNT}** |"
    echo "| Files passed | **${PASSED_FILES}** |"
    echo "| Missing copyright header | **${MISSING_COUNT}** |"
    echo "| Wrong copyright years | **${WRONG_YEARS_COUNT}** |"
    if [[ -n "${LICENSE_PATTERN}" ]]; then
      echo "| Missing SPDX-License-Identifier | **${MISSING_LICENSE_COUNT}** |"
      echo "| Invalid license identifier | **${INVALID_LICENSE_COUNT}** |"
    fi
    echo ""

    if (( MISSING_COUNT > 0 )); then
      summary_details_list "Files missing copyright header" "${MISSING_FILES[@]}"
    fi

    if (( WRONG_YEARS_COUNT > 0 )); then
      summary_details_table "Files with wrong copyright years" "${WRONG_YEAR_DETAILS[@]}"
    fi

    if [[ -n "${LICENSE_PATTERN}" ]]; then
      if (( MISSING_LICENSE_COUNT > 0 )); then
        summary_details_list "Files missing SPDX-License-Identifier" "${MISSING_LICENSE_FILES[@]}"
      fi

      if (( INVALID_LICENSE_COUNT > 0 )); then
        summary_details_table "Files with invalid license identifier" "${INVALID_LICENSE_DETAILS[@]}"
      fi
    fi

    summary_details_list "Ignored files" "${IGNORED_FILES[@]+"${IGNORED_FILES[@]}"}"

    if (( TOTAL_ERRORS == 0 )); then
      echo "> All scanned source files contain valid copyright/license headers."
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi

# ── Final verdict ────────────────────────────────────────────────

if (( TOTAL_ERRORS > 0 )); then
  echo ""
  log_error "Found ${TOTAL_ERRORS} file(s) with copyright/license issues (${MISSING_COUNT} missing copyright, ${WRONG_YEARS_COUNT} wrong years, ${MISSING_LICENSE_COUNT} missing license, ${INVALID_LICENSE_COUNT} invalid license)."
  [[ "${FAIL_ON_MISSING}" == "true" ]] && exit 1
fi

echo ""
log_info "Copyright/license check completed successfully."
exit 0
