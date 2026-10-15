#!/usr/bin/env bats
# Copyright (c) 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Tests for check-copyright-license.sh
#
# All tests run locally without GitHub Actions environment.
# They create temporary git repos with test fixtures to exercise
# copyright/license validation, year checking, ignore patterns,
# config file parsing, and license auto-detection.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-copyright-license.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

# ── Helpers ──────────────────────────────────────────────────────

# Create a temporary git repo with a commit so git history works
setup_test_repo() {
  REPO="$(mktemp -d)"
  cd "${REPO}"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
}

# Add a file to the test repo and commit it
add_file() {
  local path="$1" content="$2" year="${3:-}"
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "${content}" > "${path}"
  git add "${path}"
  if [[ -n "${year}" ]]; then
    GIT_AUTHOR_DATE="${year}-06-15T12:00:00" \
    GIT_COMMITTER_DATE="${year}-06-15T12:00:00" \
    git commit -q -m "add ${path}"
  else
    git commit -q -m "add ${path}"
  fi
}

# Set common env vars for running the script
set_env() {
  export COPYRIGHT_PATTERN='Copyright\s*(?:©|\(c\)|)\s*(\d{4})\s*(?:[-,]\s*(\d{4}))?\s+.+'
  export LICENSE_PATTERN='SPDX-License-Identifier:\s+\S+'
  export INPUT_FILE_EXTENSIONS="py,sh,c"
  export INPUT_FULL_SCAN=true
  export INPUT_SCAN_PATH="."
  export INPUT_FAIL_ON_MISSING=true
  export INPUT_SUMMARY_OUTPUT=false
  export INPUT_IGNORE_FILE=".copyrightignore"
  export INPUT_LICENSE_HEADER_LINES=30
  export INPUT_VALID_LICENSES=""
  export INPUT_COPYRIGHT_CONFIG=".copyright-config.yml"
  export INPUT_COPYRIGHT_HOLDER=""
  export GITHUB_OUTPUT="${REPO}/github_output.txt"
  export GITHUB_STEP_SUMMARY="${REPO}/github_summary.md"
  export CHANGED_FILES=""
}

teardown() {
  if [[ -n "${REPO:-}" ]]; then
    rm -rf "${REPO}"
  fi
}

# Read an output variable from GITHUB_OUTPUT
get_output() {
  local name="$1"
  # Single-line outputs
  grep "^${name}=" "${REPO}/github_output.txt" | head -1 | cut -d= -f2-
}

# ── Basic validation ─────────────────────────────────────────────

@test "check-copyright-license.sh exists and is executable" {
  [[ -f "${SCRIPT}" ]]
  chmod +x "${SCRIPT}"
  [[ -x "${SCRIPT}" ]]
}

@test "check-copyright-license.sh has valid bash syntax" {
  run bash -n "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
}

@test "fails when COPYRIGHT_PATTERN is not set" {
  setup_test_repo
  set_env
  unset COPYRIGHT_PATTERN
  run bash "${SCRIPT}"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"COPYRIGHT_PATTERN must be set"* ]]
}

# ── File with valid headers ──────────────────────────────────────

@test "passes for file with correct copyright and license headers" {
  setup_test_repo
  set_env
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output passed)" == "true" ]]
  [[ "$(get_output missing_count)" == "0" ]]
  [[ "$(get_output missing_license_count)" == "0" ]]
}

# ── Missing copyright ───────────────────────────────────────────

@test "detects missing copyright header" {
  setup_test_repo
  set_env
  add_file "src/main.py" "# SPDX-License-Identifier: Apache-2.0

print('hello')"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output missing_count)" == "1" ]]
  [[ "$(get_output passed)" == "false" ]]
}

@test "fails when missing copyright and fail-on-missing is true" {
  setup_test_repo
  set_env
  add_file "src/main.py" "print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 1 ]]
}

# ── Missing license ──────────────────────────────────────────────

@test "detects missing SPDX-License-Identifier" {
  setup_test_repo
  set_env
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.

print('hello')"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output missing_license_count)" == "1" ]]
  [[ "$(get_output passed)" == "false" ]]
}

@test "skips license check when license-pattern is empty" {
  setup_test_repo
  set_env
  export LICENSE_PATTERN=""
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output passed)" == "true" ]]
  [[ "$(get_output missing_license_count)" == "0" ]]
}

# ── Copyright year validation ────────────────────────────────────

@test "detects wrong copyright start year" {
  setup_test_repo
  set_env
  add_file "src/main.py" "# Copyright (c) 2020 Analog Devices, Inc.
# SPDX-License-Identifier: MIT" "$(date +%Y)"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output wrong_years_count)" == "1" ]]
}

@test "passes with correct year range for multi-year file" {
  setup_test_repo
  set_env
  local current_year
  current_year="$(date +%Y)"

  add_file "src/main.py" "# Copyright (c) 2020 Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('v1')" "2020"

  # Modify in current year
  printf '%s\n' "# Copyright (c) 2020-${current_year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('v2')" > "src/main.py"
  git add "src/main.py"
  git commit -q -m "update main.py"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output wrong_years_count)" == "0" ]]
}

@test "passes with comma-separated year format" {
  setup_test_repo
  set_env
  local current_year
  current_year="$(date +%Y)"

  add_file "src/main.py" "# Copyright (c) 2020 Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('v1')" "2020"

  # Modify in current year using comma format (per ADI legal guidelines)
  printf '%s\n' "# Copyright (c) 2020, ${current_year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('v2')" > "src/main.py"
  git add "src/main.py"
  git commit -q -m "update main.py"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output wrong_years_count)" == "0" ]]
}

@test "detects range when single year expected" {
  setup_test_repo
  set_env
  local current_year
  current_year="$(date +%Y)"

  add_file "src/main.py" "# Copyright (c) 2020-${current_year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('hello')"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output wrong_years_count)" == "1" ]]
}

@test "accepts copyright symbol formats" {
  setup_test_repo
  set_env
  local year
  year="$(date +%Y)"

  # Copyright with unicode symbol
  add_file "src/unicode.py" "# Copyright © ${year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('ok')"

  # Copyright without symbol
  add_file "src/plain.py" "# Copyright ${year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('ok')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output missing_count)" == "0" ]]
}

# ── License allowlist (valid-licenses) ───────────────────────────

@test "passes when license is in valid-licenses list" {
  setup_test_repo
  set_env
  export INPUT_VALID_LICENSES="Apache-2.0,MIT"
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output invalid_license_count)" == "0" ]]
}

@test "detects license not in valid-licenses list" {
  setup_test_repo
  set_env
  export INPUT_VALID_LICENSES="Apache-2.0"
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.
# SPDX-License-Identifier: GPL-3.0-only

print('hello')"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output invalid_license_count)" == "1" ]]
  [[ "$(get_output passed)" == "false" ]]
}

@test "accepts LicenseRef-* custom identifiers" {
  setup_test_repo
  set_env
  export INPUT_VALID_LICENSES="LicenseRef-ADI-Proprietary"
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Analog Devices, Inc.
# SPDX-License-Identifier: LicenseRef-ADI-Proprietary

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output invalid_license_count)" == "0" ]]
}

# ── License auto-detection ───────────────────────────────────────

@test "auto-detects license from SPDX identifier in LICENSE file" {
  setup_test_repo
  set_env
  add_file "LICENSE" "SPDX-License-Identifier: BSD-3-Clause

Copyright (c) 2024 Test Corp. All rights reserved."

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: BSD-3-Clause

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output detected_license)" == "BSD-3-Clause" ]]
}

@test "auto-detects Apache-2.0 from license text" {
  setup_test_repo
  set_env
  add_file "LICENSE" "                             Apache License
                         Version 2.0, January 2004
                      http://www.apache.org/licenses/"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: Apache-2.0

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output detected_license)" == "Apache-2.0" ]]
}

@test "auto-detects MIT from license text" {
  setup_test_repo
  set_env
  add_file "LICENSE" "MIT License

Copyright (c) 2024 Test Corp."

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output detected_license)" == "MIT" ]]
}

@test "detected license is added to allowlist when valid-licenses is set" {
  setup_test_repo
  set_env
  export INPUT_VALID_LICENSES="MIT"

  add_file "LICENSE" "SPDX-License-Identifier: Apache-2.0

Apache License text..."

  # File uses Apache-2.0 (detected), not MIT (explicit in valid-licenses)
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: Apache-2.0

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output invalid_license_count)" == "0" ]]
}

# ── .copyright-config.yml ───────────────────────────────────────

@test "loads project-license from .copyright-config.yml" {
  setup_test_repo
  set_env

  add_file ".copyright-config.yml" "project-license: BSD-3-Clause

allowed-licenses:
  - MIT"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: BSD-3-Clause

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output invalid_license_count)" == "0" ]]
}

@test "config allowed-licenses rejects unlisted license" {
  setup_test_repo
  set_env

  add_file ".copyright-config.yml" "project-license: Apache-2.0

allowed-licenses:
  - MIT"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: GPL-3.0-only

print('hello')"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output invalid_license_count)" == "1" ]]
}

@test "config ignores inline comments" {
  setup_test_repo
  set_env

  add_file ".copyright-config.yml" "project-license: Apache-2.0

allowed-licenses:
  - MIT  # vendored utility
  - BSD-3-Clause  # imported driver"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
}

# ── Ignore file (.copyrightignore) ──────────────────────────────

@test "ignores files matching .copyrightignore patterns" {
  setup_test_repo
  set_env
  add_file ".copyrightignore" "vendor/"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  # This file has no headers but should be ignored
  add_file "vendor/lib.py" "print('vendored')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output total_scanned)" == "1" ]]
  [[ "$(get_output ignored_count)" == "1" ]]
}

@test "ignores files matching glob patterns" {
  setup_test_repo
  set_env
  add_file ".copyrightignore" "*.sh"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  add_file "scripts/build.sh" "echo 'no header'"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output total_scanned)" == "1" ]]
}

# ── File extension filtering ─────────────────────────────────────

@test "only scans configured file extensions" {
  setup_test_repo
  set_env
  export INPUT_FILE_EXTENSIONS="py"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  # .sh file should not be scanned when only py is configured
  add_file "scripts/build.sh" "echo 'no header'"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output total_scanned)" == "1" ]]
}

@test "rejects invalid file extension characters" {
  setup_test_repo
  set_env
  export INPUT_FILE_EXTENSIONS="py;rm -rf"

  run bash "${SCRIPT}"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"Invalid file extension"* ]]
}

# ── License header line limit ────────────────────────────────────

@test "license found within header line limit passes" {
  setup_test_repo
  set_env
  export INPUT_LICENSE_HEADER_LINES=5

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
#
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output missing_license_count)" == "0" ]]
}

@test "license beyond header line limit is not detected" {
  setup_test_repo
  set_env
  export INPUT_LICENSE_HEADER_LINES=2

  # Copyright on line 1, license on line 4 (beyond limit of 2)
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
print('line2')
print('line3')
# SPDX-License-Identifier: MIT"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output missing_license_count)" == "1" ]]
}

# ── Multiple files ───────────────────────────────────────────────

@test "scans multiple files and reports correct totals" {
  setup_test_repo
  set_env
  local year
  year="$(date +%Y)"

  add_file "src/good.py" "# Copyright (c) ${year} Test Corp.
# SPDX-License-Identifier: MIT
print('ok')"

  add_file "src/no_copyright.py" "# SPDX-License-Identifier: MIT
print('missing copyright')"

  add_file "src/no_license.py" "# Copyright (c) ${year} Test Corp.
print('missing license')"

  add_file "src/no_header.sh" "echo 'nothing'"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output total_scanned)" == "4" ]]
  [[ "$(get_output missing_count)" == "2" ]]
  [[ "$(get_output missing_license_count)" == "2" ]]
}

# ── Job summary ──────────────────────────────────────────────────

@test "generates job summary when summary-output is true" {
  setup_test_repo
  set_env
  export INPUT_SUMMARY_OUTPUT=true
  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ -f "${REPO}/github_summary.md" ]]
  grep -q "Copyright & License Check Results" "${REPO}/github_summary.md"
}

@test "summary includes detected license" {
  setup_test_repo
  set_env
  export INPUT_SUMMARY_OUTPUT=true

  add_file "LICENSE" "MIT License

Copyright (c) 2024 Test"

  add_file "src/main.py" "# Copyright (c) $(date +%Y) Test Corp.
# SPDX-License-Identifier: MIT

print('hello')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  grep -q "MIT" "${REPO}/github_summary.md"
}

# ── Report-only mode ─────────────────────────────────────────────

@test "report-only mode exits 0 even with violations" {
  setup_test_repo
  set_env
  export INPUT_FAIL_ON_MISSING=false
  add_file "src/main.py" "print('no headers at all')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output passed)" == "false" ]]
}

# ── No files to scan ─────────────────────────────────────────────

@test "passes when no files match extensions" {
  setup_test_repo
  set_env
  export INPUT_FILE_EXTENSIONS="rs"
  add_file "src/main.py" "print('not rust')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output total_scanned)" == "0" ]]
}

# ── Third-party copyright holder detection ──────────────────────

@test "third-party copyright warns but does not fail" {
  setup_test_repo
  set_env
  export INPUT_COPYRIGHT_HOLDER="Analog Devices"

  add_file "deps/lib.py" "# Copyright (C) 2014 Paul Cercueil <paul@example.com>
# SPDX-License-Identifier: LGPL-2.1-or-later

def helper(): pass"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output third_party_count)" == "1" ]]
  [[ "$(get_output passed)" == "true" ]]
  [[ "${output}" == *"Third-party copyright"* ]]
}

@test "ADI copyright validates years normally when holder is set" {
  setup_test_repo
  set_env
  export INPUT_COPYRIGHT_HOLDER="Analog Devices"

  add_file "src/main.py" "# Copyright (c) 2020 Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('v1')" "$(date +%Y)"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  [[ "$(get_output wrong_years_count)" == "1" ]]
  [[ "$(get_output third_party_count)" == "0" ]]
}

@test "missing copyright still fails when holder is set" {
  setup_test_repo
  set_env
  export INPUT_COPYRIGHT_HOLDER="Analog Devices"

  add_file "src/main.py" "print('no header at all')"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 1 ]]
  [[ "$(get_output missing_count)" == "1" ]]
}

@test "no holder configured treats all copyrights equally" {
  setup_test_repo
  set_env
  export INPUT_COPYRIGHT_HOLDER=""

  add_file "deps/lib.py" "# Copyright (C) 2014 Paul Cercueil <paul@example.com>
# SPDX-License-Identifier: MIT

def helper(): pass" "2014"

  export INPUT_FAIL_ON_MISSING=false
  run bash "${SCRIPT}"
  # With no holder set, third-party detection is disabled
  [[ "$(get_output third_party_count)" == "0" ]]
}

@test "mixed ADI and third-party files reports correctly" {
  setup_test_repo
  set_env
  export INPUT_COPYRIGHT_HOLDER="Analog Devices"
  local year
  year="$(date +%Y)"

  add_file "src/main.py" "# Copyright (c) ${year} Analog Devices, Inc.
# SPDX-License-Identifier: MIT
print('adi code')"

  add_file "deps/vendor.py" "# Copyright (c) 2018 Some Other Corp.
# SPDX-License-Identifier: BSD-3-Clause
print('vendored')" "2018"

  run bash "${SCRIPT}"
  [[ "${status}" -eq 0 ]]
  [[ "$(get_output third_party_count)" == "1" ]]
  [[ "$(get_output passed)" == "true" ]]
}
