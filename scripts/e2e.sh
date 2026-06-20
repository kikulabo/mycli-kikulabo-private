#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MYCLI="${REPO_ROOT}/mycli"

START_US=$(perl -MTime::HiRes=gettimeofday -e 'my ($s,$u)=gettimeofday(); printf "%d\n",$s*1_000_000+$u')
JAEGER_HTTP="http://localhost:16686"
OTLP_ENDPOINT="http://localhost:4318"
JAEGER_PID=""

PASS=0
FAIL=0
LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT=0
_STDERR_TMP=$(mktemp)

cleanup() {
  rm -f "${_STDERR_TMP}"
  if [ -n "${JAEGER_PID}" ]; then
    kill "${JAEGER_PID}" 2>/dev/null || true
  fi
}
trap 'cleanup' EXIT

# ── Jaeger 起動 ──────────────────────────────────────────────────────────────
start_jaeger() {
  if mise exec -- jaeger --version >/dev/null 2>&1; then
    mise exec -- jaeger \
      --collector.otlp.http.host-port=":4318" \
      --query.http-server.host-port=":16686" >/dev/null 2>&1 &
    JAEGER_PID=$!
  else
    docker compose -f "${REPO_ROOT}/compose.yaml" up -d jaeger
  fi
  # wait until Jaeger API responds
  for _ in $(seq 1 20); do
    if curl -sf "${JAEGER_HTTP}/api/services" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "ERROR: Jaeger did not start in time" >&2
  exit 1
}

# ── コマンド実行ヘルパー ──────────────────────────────────────────────────────
run_cmd() {
  set +e
  LAST_STDOUT=$("${MYCLI}" "$@" 2>"${_STDERR_TMP}")
  LAST_EXIT=$?
  set -e
  LAST_STDERR=$(cat "${_STDERR_TMP}")
}

run_cmd_otlp() {
  set +e
  LAST_STDOUT=$(
    MYCLI_TRACES_EXPORTER=otlp \
      MYCLI_OTLP_ENDPOINT="${OTLP_ENDPOINT}" \
      OTEL_RESOURCE_ATTRIBUTES='' \
      perl -e 'alarm 10; exec @ARGV' "${MYCLI}" "$@" 2>"${_STDERR_TMP}"
  )
  LAST_EXIT=$?
  set -e
  LAST_STDERR=$(cat "${_STDERR_TMP}")
}

# ── アサーションヘルパー ─────────────────────────────────────────────────────
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

# $1: スペース区切りの期待 Span 名リスト  $2: 説明
expect_trace_span_names() {
  local expected_names="$1"
  local desc="$2"
  local traces
  traces=$(curl -sf \
    "${JAEGER_HTTP}/api/traces?service=mycli&start=${START_US}&limit=1")
  for name in ${expected_names}; do
    if printf '%s' "${traces}" | jq -e \
      --arg n "${name}" \
      '[.data[].spans[].operationName] | map(select(. == $n)) | length > 0' \
      >/dev/null 2>&1; then
      echo "PASS: ${desc} (span '${name}' found)"
      PASS=$((PASS + 1))
    else
      echo "FAIL: ${desc} (span '${name}' not found)"
      FAIL=$((FAIL + 1))
    fi
  done
}

expect_trace_status_ok() {
  local desc="$1"
  local traces
  traces=$(curl -sf \
    "${JAEGER_HTTP}/api/traces?service=mycli&start=${START_US}&limit=1")
  local not_ok
  not_ok=$(printf '%s' "${traces}" | jq \
    '[.data[].spans[].tags[] | select(.key=="otel.status_code" and .value!="OK")] | length')
  if [ "${not_ok}" -eq 0 ]; then
    echo "PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${desc} (found ${not_ok} non-OK status tags)"
    FAIL=$((FAIL + 1))
  fi
}

# ── テストケース ─────────────────────────────────────────────────────────────

# Test: mycli --help
run_cmd --help
expect_exit_code 0 "mycli --help exits 0"
expect_stdout_contains "mycli" "mycli --help stdout contains 'mycli'"

# Test: mycli hello
run_cmd hello
expect_exit_code 0 "mycli hello exits 0"
expect_stdout_contains "Hello, World!" "mycli hello stdout contains 'Hello, World!'"

# Test: invalid exporter
set +e
LAST_STDOUT=$(MYCLI_TRACES_EXPORTER=invalid "${MYCLI}" hello 2>"${_STDERR_TMP}")
LAST_EXIT=$?
set -e
LAST_STDERR=$(cat "${_STDERR_TMP}")
expect_exit_code 1 "MYCLI_TRACES_EXPORTER=invalid exits 1"
expect_stderr_contains "unknown MYCLI_TRACES_EXPORTER" "MYCLI_TRACES_EXPORTER=invalid stderr contains error"

# Test: otlp without endpoint
set +e
LAST_STDOUT=$(MYCLI_TRACES_EXPORTER=otlp "${MYCLI}" hello 2>"${_STDERR_TMP}")
LAST_EXIT=$?
set -e
LAST_STDERR=$(cat "${_STDERR_TMP}")
expect_exit_code 1 "MYCLI_TRACES_EXPORTER=otlp without endpoint exits 1"
expect_stderr_contains "MYCLI_OTLP_ENDPOINT is required" "MYCLI_TRACES_EXPORTER=otlp without endpoint stderr contains error"

# Test: OTel traces (requires Jaeger)
start_jaeger
run_cmd_otlp hello
expect_exit_code 0 "MYCLI_TRACES_EXPORTER=otlp mycli hello exits 0"
expect_stdout_contains "Hello, World!" "MYCLI_TRACES_EXPORTER=otlp mycli hello stdout contains 'Hello, World!'"
expect_trace_span_names "main hello" "Jaeger has 'main' and 'hello' spans"
expect_trace_status_ok "all spans have status OK"

# ── サマリー ─────────────────────────────────────────────────────────────────
echo ""
printf 'Results: %d passed, %d failed\n' "${PASS}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
