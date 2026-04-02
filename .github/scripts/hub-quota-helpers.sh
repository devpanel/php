#!/bin/bash
# Shared Docker Hub quota helpers.
#
# Source this file in any run block that needs to probe Docker Hub pull quota.
# TOKEN_MAX_AGE defaults to 240 s but can be overridden by the caller before
# sourcing this file.
#
# Requires: bash 4+, curl, jq

# Default token max age (seconds before a token is considered stale).
# Callers may override this before sourcing this file.
TOKEN_MAX_AGE="${TOKEN_MAX_AGE:-240}"

# Internal quota-probe token state.  These variables are managed entirely
# by the refresh_anon_quota_token / refresh_auth_quota_token helpers below;
# callers should not read or write them directly.
_HUB_QUOTA_ANON_TOKEN=""
_HUB_QUOTA_ANON_TOKEN_TIME=0
_HUB_QUOTA_AUTH_TOKEN=""
_HUB_QUOTA_AUTH_TOKEN_TIME=0

# refresh_hub_token VARNAME [username [password]]
# Fetches a ratelimitpreview/test:pull-scoped token from auth.docker.io.
# Without username/password the token is anonymous (IP-based quota); with
# username and password it is authenticated (account-based quota).  Skips
# the fetch if the token is still fresh (< TOKEN_MAX_AGE seconds old).
# Updates VARNAME and ${VARNAME}_TIME globals in the calling scope.
# Returns 0 when a valid token is available, 1 when the fetch failed.
refresh_hub_token() {
  local _varname="$1" _username="${2:-}" _password="${3:-}"
  local _now _time_var
  _now="$(date +%s)"
  _time_var="${_varname}_TIME"
  if [[ -n "${!_varname}" ]] && (( _now - ${!_time_var:-0} < TOKEN_MAX_AGE )); then
    return 0
  fi
  local _curl_args=(-sf --connect-timeout 5 --max-time 15)
  if [[ -n "${_username}" ]] && [[ -n "${_password}" ]]; then
    _curl_args+=(--user "${_username}:${_password}")
  fi
  local _json _new_token
  _json="$(curl "${_curl_args[@]}" \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" \
    2>/dev/null)" || _json=""
  _new_token="$(printf '%s' "${_json}" | jq -r '.token // ""' 2>/dev/null)" \
    || _new_token=""
  if [[ -n "${_new_token}" ]]; then
    printf -v "${_varname}" '%s' "${_new_token}"
    printf -v "${_varname}_TIME" '%s' "${_now}"
    return 0
  fi
  return 1
}

# hub_pull_remaining TOKEN
# Sends a HEAD request (not counted against quota) to the Docker Hub
# rate-limit probe endpoint and prints the remaining pull count:
#   "<n>"       numeric remaining pulls
#   "unlimited" 2xx response without a RateLimit-Remaining header
#               (Pro / Team / Business plan with no rate limit)
#   ""          probe failed (no token, network error, or non-2xx)
# Use --head (not -X HEAD): MITM proxies on GitHub-hosted runners
# downgrade HTTP/2 to HTTP/1.1; -X HEAD over HTTP/1.1 makes curl
# wait for a body that never arrives and times out (exit 28).
hub_pull_remaining() {
  local _token="$1"
  [[ -z "${_token}" ]] && { echo ""; return; }
  local _tmpheaders _http_code _headers _remaining
  _tmpheaders="$(mktemp)"
  _http_code="$(curl -s --connect-timeout 5 --max-time 15 \
    -H "Authorization: Bearer ${_token}" \
    --head -D "${_tmpheaders}" -o /dev/null \
    -w '%{http_code}' \
    "https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest" \
    2>/dev/null)" || _http_code=""
  _headers="$(cat "${_tmpheaders}" 2>/dev/null || true)"
  rm -f "${_tmpheaders}"
  if [[ "${_http_code:0:1}" == "2" ]]; then
    _remaining="$(printf '%s' "${_headers}" \
      | grep -i '^ratelimit-remaining:' \
      | grep -oE '[0-9]+' | head -1)" || _remaining=""
    echo "${_remaining:-unlimited}"
  fi
  # Non-2xx or empty http_code: print nothing (caller treats as failed probe).
  # Always return 0: callers detect failure via empty stdout, not exit status,
  # so a transient probe failure must not abort callers running under set -e.
  return 0
}

# refresh_anon_quota_token
# Convenience wrapper: refresh the internal anonymous quota-probe token.
# Equivalent to: refresh_hub_token _HUB_QUOTA_ANON_TOKEN
refresh_anon_quota_token() {
  refresh_hub_token _HUB_QUOTA_ANON_TOKEN
}

# refresh_auth_quota_token
# Convenience wrapper: refresh the internal authenticated quota-probe token
# using credentials from the DOCKERHUB_USERNAME and DOCKERHUB_TOKEN
# environment variables.  Returns 0 when a valid token is available,
# 1 when the fetch failed.  On failure, emits a categorised ::error:: message
# to stderr (network/TLS/DNS failure vs. credential rejection) plus a
# ::debug:: line with the raw response body to aid diagnostics.
refresh_auth_quota_token() {
  if [[ -z "${DOCKERHUB_USERNAME:-}" ]] || [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "::error::DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must be set." \
         "Verify that the secrets are configured for this repository." >&2
    return 1
  fi
  # Fast-path: cached token is still fresh.
  local _now
  _now="$(date +%s)"
  if [[ -n "${_HUB_QUOTA_AUTH_TOKEN}" ]] \
      && (( _now - _HUB_QUOTA_AUTH_TOKEN_TIME < TOKEN_MAX_AGE )); then
    return 0
  fi
  # Fetch a new token: body → temp file, HTTP status code → stdout, curl
  # errors → temp file.  This lets us branch on the exact HTTP status code
  # rather than heuristically matching strings inside the response body.
  local _rc=0 _body _http_code _curl_err _token _tmpbody _tmpstderr
  _tmpbody="$(mktemp)"
  _tmpstderr="$(mktemp)"
  _http_code="$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
    --user "${DOCKERHUB_USERNAME}:${DOCKERHUB_TOKEN}" \
    --output "${_tmpbody}" \
    --write-out '%{http_code}' \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" \
    2>"${_tmpstderr}")" || _rc=$?
  _body="$(cat "${_tmpbody}" 2>/dev/null || true)"
  _curl_err="$(cat "${_tmpstderr}" 2>/dev/null || true)"
  rm -f "${_tmpbody}" "${_tmpstderr}"
  _token="$(printf '%s' "${_body}" | jq -r '.token // ""' 2>/dev/null)" \
    || _token=""
  if [[ -n "${_token}" ]]; then
    _HUB_QUOTA_AUTH_TOKEN="${_token}"
    _HUB_QUOTA_AUTH_TOKEN_TIME="${_now}"
    return 0
  fi
  # Emit a categorised error so callers don't need to re-implement this logic.
  if (( _rc != 0 )); then
    echo "::error::Network/TLS/DNS failure contacting the Docker Hub auth endpoint" \
         "(curl exit ${_rc})." \
         "Check runner connectivity and Docker Hub status before retrying." \
         "To retry: click 'Re-run failed jobs' on this workflow run's summary page." >&2
  elif [[ "${_http_code}" == "401" ]] || [[ "${_http_code}" == "403" ]]; then
    echo "::error::Docker Hub rejected the credentials (HTTP ${_http_code})." \
         "Verify that the DOCKERHUB_USERNAME and DOCKERHUB_TOKEN secrets are set and valid." \
         "To retry: click 'Re-run failed jobs' on this workflow run's summary page." >&2
  else
    echo "::error::Could not obtain a Docker Hub auth token (HTTP ${_http_code:-unknown})." \
         "Verify that DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are set and valid," \
         "and that the Docker Hub auth endpoint is reachable." \
         "To retry: click 'Re-run failed jobs' on this workflow run's summary page." >&2
  fi
  # Build debug info from curl stderr (network errors) + response body.
  local _debug_info="${_curl_err}"
  [[ -n "${_debug_info}" ]] && [[ -n "${_body}" ]] && _debug_info+=$'\n'
  _debug_info+="${_body}"
  if [[ -n "${_debug_info}" ]]; then
    # Sanitize before embedding in a GitHub Actions workflow command:
    # escape % → %25, CR → %0D, LF → %0A to prevent log/command injection.
    local _safe_debug="${_debug_info//'%'/'%25'}"
    _safe_debug="${_safe_debug//$'\r'/'%0D'}"
    _safe_debug="${_safe_debug//$'\n'/'%0A'}"
    echo "::debug::Docker Hub auth response: ${_safe_debug}" >&2
  fi
  return 1
}

# anon_quota_remaining
# Convenience wrapper: refresh the internal anonymous quota-probe token if
# needed, then print the anonymous pull quota remaining.
anon_quota_remaining() {
  refresh_anon_quota_token || true
  hub_pull_remaining "${_HUB_QUOTA_ANON_TOKEN}"
}

# auth_quota_remaining
# Convenience wrapper: refresh the internal authenticated quota-probe token if
# needed, then print the authenticated pull quota remaining.
auth_quota_remaining() {
  refresh_auth_quota_token || true
  hub_pull_remaining "${_HUB_QUOTA_AUTH_TOKEN}"
}
