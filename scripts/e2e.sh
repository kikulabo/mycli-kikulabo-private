#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MYCLI="${REPO_ROOT}/mycli"

PASS=0
FAIL=0
LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT=0
_STDERR_TMP=$(mktemp)
trap 'rm -f "${_STDERR_TMP}"' EXIT

run_cmd() {
  set +e
  LAST_STDOUT=$("${MYCLI}" "$@" 2>"${_STDERR_TMP}")
  LAST_EXIT=$?
  set -e
  LAST_STDERR=$(cat "${_STDERR_TMP}")
}

expect_exit_code() {
  local expected="$1"
  local desc="$2"
  if [ "${LAST_EXIT}" -eq "${expected}" ]; then
    echo "PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${desc} (expected exit ${expected}, got ${LAST_EXIT})"
    FAIL=$((FAIL + 1))
  fi
}

expect_stderr_contains() {
  local expected="$1"
  local desc="$2"
  if printf '%s' "${LAST_STDERR}" | grep -qF "${expected}"; then
    echo "PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${desc} (expected stderr to contain '${expected}')"
    printf '  stderr: %s\n' "${LAST_STDERR}"
    FAIL=$((FAIL + 1))
  fi
}

expect_stdout_contains() {
  local expected="$1"
  local desc="$2"
  if printf '%s' "${LAST_STDOUT}" | grep -qF "${expected}"; then
    echo "PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${desc} (expected stdout to contain '${expected}')"
    printf '  stdout: %s\n' "${LAST_STDOUT}"
    FAIL=$((FAIL + 1))
  fi
}

# Test: mycli --help
run_cmd --help
expect_exit_code 0 "mycli --help exits 0"
expect_stdout_contains "mycli" "mycli --help stdout contains 'mycli'"

# Summary
echo ""
printf 'Results: %d passed, %d failed\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
