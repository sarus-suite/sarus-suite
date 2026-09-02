#!/usr/bin/env bash
#
# Spinner-only subset adapted from Clack for Bash v1.1.0.
# Upstream: https://github.com/ibrahimhajjaj/clack-bash
# License: MIT; see LICENSE in this directory.
#
# The full upstream clack.sh is intentionally not needed for non-interactive
# bundle builds.  Keep these public function names compatible with upstream.

__CLACK_SPINNER_PID=""
__CLACK_SPINNER_MSG=""
__CLACK_SPINNER_INDICATOR="dots"
__CLACK_SPINNER_START_TIME=0

__clack_spinner_format_timer() {
  local now duration minutes seconds
  now="$(date +%s)"
  duration=$((now - __CLACK_SPINNER_START_TIME))
  minutes=$((duration / 60))
  seconds=$((duration % 60))
  if [ "${minutes}" -gt 0 ]; then
    printf '[%dm %ds]' "${minutes}" "${seconds}"
  else
    printf '[%ds]' "${seconds}"
  fi
}

__clack_spinner_loop() {
  local frames='|/-\\' frame=0
  while :; do
    printf '\r\033[K%s  %s' "${frames:frame++%${#frames}:1}" "${__CLACK_SPINNER_MSG}" >&2
    sleep 0.1
  done
}

clack_spinner_start() {
  __CLACK_SPINNER_MSG="${1:-Loading}"
  __CLACK_SPINNER_INDICATOR="${2:-dots}"
  __CLACK_SPINNER_START_TIME="$(date +%s)"
  __clack_spinner_loop &
  __CLACK_SPINNER_PID=$!
}

__clack_spinner_finish() {
  local marker="$1"
  local message="$2"
  local timer_suffix=""

  if [ -n "${__CLACK_SPINNER_PID}" ]; then
    kill "${__CLACK_SPINNER_PID}" 2>/dev/null || true
    wait "${__CLACK_SPINNER_PID}" 2>/dev/null || true
    __CLACK_SPINNER_PID=""
  fi
  if [ "${__CLACK_SPINNER_INDICATOR}" = timer ]; then
    timer_suffix=" $(__clack_spinner_format_timer)"
  fi
  printf '\r\033[K%s  %s%s\n' "${marker}" "${message}" "${timer_suffix}" >&2
}

clack_spinner_stop() {
  __clack_spinner_finish '[done]' "${1:-Done}"
}

clack_spinner_error() {
  __clack_spinner_finish '[fail]' "${1:-Failed}"
}

clack_spinner_cancel() {
  __clack_spinner_finish '[cancelled]' "${1:-Cancelled}"
}
