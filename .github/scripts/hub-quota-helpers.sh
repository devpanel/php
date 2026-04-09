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

# refresh_hub_token VARNAME [creds_file]
# Fetches a ratelimitpreview/test:pull-scoped token from auth.docker.io.
# Without creds_file the token is anonymous (IP-based quota); with
# creds_file it is authenticated (account-based quota).  Skips the
# fetch if the token is still fresh (< TOKEN_MAX_AGE seconds old).
# Updates VARNAME and ${VARNAME}_TIME globals in the calling scope.
# Returns 0 when a valid token is available, 1 when the fetch failed.
refresh_hub_token() {
  local _varname="$1" _creds="${2:-}"
  local _now _time_var
  _now="$(date +%s)"
  _time_var="${_varname}_TIME"
  if [[ -n "${!_varname}" ]] && (( _now - ${!_time_var:-0} < TOKEN_MAX_AGE )); then
    return 0
  fi
  local _curl_args=(-sf --connect-timeout 5 --max-time 15)
  [[ -n "${_creds}" ]] && _curl_args+=(--netrc-file "${_creds}")
  local _json _new_token
  _json="$(curl "${_curl_args[@]}" \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" \
    2>/dev/null)" || _json=""
  _new_token="$(printf '%s' "${_json}" | jq -r '.token // ""' 2>/dev/null)" \
    || _new_token=""
  printf -v "${_varname}" '%s' "${_new_token}"
  printf -v "${_varname}_TIME" '%s' "$(date +%s)"
  [[ -n "${_new_token}" ]]
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
  # Non-2xx or empty http_code: print nothing (caller treats as failed).
}

# refresh_anon_quota_token
# Convenience wrapper: refresh the internal anonymous quota-probe token.
# Equivalent to: refresh_hub_token _HUB_QUOTA_ANON_TOKEN
refresh_anon_quota_token() {
  refresh_hub_token _HUB_QUOTA_ANON_TOKEN
}

# refresh_auth_quota_token [creds_file]
# Convenience wrapper: refresh the internal authenticated quota-probe token.
# If creds_file is omitted, a temporary netrc-format file is created from the
# DOCKERHUB_USERNAME and DOCKERHUB_TOKEN environment variables and cleaned up
# after the token fetch.  If neither is provided the fetch will fail (return 1).
refresh_auth_quota_token() {
  local _creds_file="${1:-}"
  local _tmp_creds=""
  if [[ -z "${_creds_file}" ]] \
       && [[ -n "${DOCKERHUB_USERNAME:-}" ]] \
       && [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
    _tmp_creds="$(umask 077; mktemp)"
    printf 'machine auth.docker.io login %s password %s\n' \
      "${DOCKERHUB_USERNAME}" "${DOCKERHUB_TOKEN}" > "${_tmp_creds}"
    _creds_file="${_tmp_creds}"
  fi
  refresh_hub_token _HUB_QUOTA_AUTH_TOKEN "${_creds_file}"
  local _ret=$?
  [[ -n "${_tmp_creds}" ]] && rm -f "${_tmp_creds}"
  return ${_ret}
}

# anon_quota_remaining
# Convenience wrapper: print the anonymous pull quota remaining using the
# internal anonymous quota-probe token.
anon_quota_remaining() {
  hub_pull_remaining "${_HUB_QUOTA_ANON_TOKEN}"
}

# auth_quota_remaining
# Convenience wrapper: print the authenticated pull quota remaining using the
# internal authenticated quota-probe token.
auth_quota_remaining() {
  hub_pull_remaining "${_HUB_QUOTA_AUTH_TOKEN}"
}
