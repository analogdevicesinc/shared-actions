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
# Tests for build-deb.sh
#
# Fast tests (validation, template processing) run anywhere.
# The full-build test needs apt/network and root; it is skipped unless
# RUN_FULL_BUILD=1 is set. It is expected to be exercised in the
# deb-generator-action-test.yml workflow, where network access exists.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../build-deb.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/sample-pkg"
  WORKDIR="$(mktemp -d)"
  cp -r "${FIXTURE}" "${WORKDIR}/sample-pkg"
}

teardown() {
  [ -n "${WORKDIR}" ] && rm -rf "${WORKDIR}"
}

@test "build-deb.sh exists and is executable" {
  [ -x "${SCRIPT}" ]
}

@test "build-deb.sh has valid bash syntax" {
  run bash -n "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "fails when VERSION is not set" {
  run env -u VERSION WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"VERSION is required"* ]]
}

@test "fails when packaging/debian is missing" {
  rm -rf "${WORKDIR}/sample-pkg/packaging"
  run env VERSION=1.0.0 WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"packaging/debian/ directory not found"* ]]
}

@test "honors a custom CONTROL_PATH in the not-found error" {
  run env VERSION=1.0.0 WORKING_DIRECTORY="${WORKDIR}/sample-pkg" \
    CONTROL_PATH="debian/custom" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"debian/custom/ directory not found"* ]]
}

@test "fails when working directory does not exist" {
  run env VERSION=1.0.0 WORKING_DIRECTORY="${WORKDIR}/does-not-exist" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"working directory not found"* ]]
}

@test "rejects a VERSION with unsafe characters" {
  run env VERSION='1.0;rm -rf' WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Debian upstream version"* ]]
}

@test "rejects a VERSION not starting with a digit" {
  run env VERSION='v1.0.0' WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Debian upstream version"* ]]
}

@test "reads package name from control Source: field" {
  # Grep the same way the script does and confirm the fixture is well-formed.
  run grep -m1 '^Source:' "${WORKDIR}/sample-pkg/packaging/debian/control"
  [ "${status}" -eq 0 ]
  name="$(awk '{print $2}' <<< "${output}")"
  [ "${name}" = "sample-pkg" ]
}

@test "fixture control has the @ARCHITECTURE@ placeholder" {
  run grep -q '@ARCHITECTURE@' "${WORKDIR}/sample-pkg/packaging/debian/control"
  [ "${status}" -eq 0 ]
}

@test "fixture changelog has @VERSION@ and @DATE@ placeholders" {
  run grep -q '@VERSION@' "${WORKDIR}/sample-pkg/packaging/debian/changelog"
  [ "${status}" -eq 0 ]
  run grep -q '@DATE@' "${WORKDIR}/sample-pkg/packaging/debian/changelog"
  [ "${status}" -eq 0 ]
}

@test "full build produces a .deb (needs apt/network/root)" {
  if [ "${RUN_FULL_BUILD:-0}" != "1" ]; then
    skip "set RUN_FULL_BUILD=1 to run the full build (requires apt + network)"
  fi
  export GITHUB_WORKSPACE="${WORKDIR}"
  run env VERSION=1.0.0 WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  run bash -c "ls ${WORKDIR}/artifacts/*.deb"
  [ "${status}" -eq 0 ]
}

@test "full build does not mutate the source tree (needs apt/network/root)" {
  if [ "${RUN_FULL_BUILD:-0}" != "1" ]; then
    skip "set RUN_FULL_BUILD=1 to run the full build (requires apt + network)"
  fi
  export GITHUB_WORKSPACE="${WORKDIR}"
  run env VERSION=1.0.0 WORKING_DIRECTORY="${WORKDIR}/sample-pkg" bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  # The caller's packaging/ dir must still be intact (build ran in a temp copy).
  [ -d "${WORKDIR}/sample-pkg/packaging/debian" ]
  # No debian/ should have been created at the source root.
  [ ! -d "${WORKDIR}/sample-pkg/debian" ]
}
