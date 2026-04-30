#!/bin/bash
# Turn on bash's job control.

# Escape a value for safe use as a sed replacement string when using | as the delimiter.
# Escapes backslash, ampersand, and pipe — the characters special in sed replacement with this delimiter.
_escape_sed() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

cp /templates/apache2.conf /etc/apache2/apache2.conf
cp /templates/000-default.conf /etc/apache2/sites-enabled/000-default.conf
cp /templates/php.ini "${PHP_EXT_DIR}/zz-www.ini"

# Substitute in php.ini values.
if [ -n "${PHP_CLEAR_ENV:-}" ]; then
  _v=$(_escape_sed "${PHP_CLEAR_ENV}"); sed -i "s|{{PHP_CLEAR_ENV}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_MEMORY_LIMIT:-}" ]; then
  _v=$(_escape_sed "${PHP_MEMORY_LIMIT}"); sed -i "s|{{PHP_MEMORY_LIMIT}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_UPLOAD_MAX_FILESIZE:-}" ]; then
  _v=$(_escape_sed "${PHP_UPLOAD_MAX_FILESIZE}"); sed -i "s|{{PHP_UPLOAD_MAX_FILESIZE}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_POST_MAX_SIZE:-}" ]; then
  _v=$(_escape_sed "${PHP_POST_MAX_SIZE}"); sed -i "s|{{PHP_POST_MAX_SIZE}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_MAX_EXECUTION_TIME:-}" ]; then
  _v=$(_escape_sed "${PHP_MAX_EXECUTION_TIME}"); sed -i "s|{{PHP_MAX_EXECUTION_TIME}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_MAX_INPUT_TIME:-}" ]; then
  _v=$(_escape_sed "${PHP_MAX_INPUT_TIME}"); sed -i "s|{{PHP_MAX_INPUT_TIME}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi
if [ -n "${PHP_MAX_INPUT_VARS:-}" ]; then
  _v=$(_escape_sed "${PHP_MAX_INPUT_VARS}"); sed -i "s|{{PHP_MAX_INPUT_VARS}}|${_v}|" "${PHP_EXT_DIR}/zz-www.ini"
fi

# Add custom php.ini if it exists.
[ -f "$PHP_CUSTOM_INI" ] && cp "$PHP_CUSTOM_INI" "${PHP_EXT_DIR}/zzz-www-custom.ini"

# Custom Environment variables in /etc/apache2/sites-enabled/000-default.conf.
if [ -n "${APP_ROOT:-}" ]; then
  _v=$(_escape_sed "${APP_ROOT}"); sed -i "s|{{APP_ROOT}}|${_v}|" /etc/apache2/sites-enabled/000-default.conf
fi
if [ -n "${WEB_ROOT:-}" ]; then
  _v=$(_escape_sed "${WEB_ROOT}"); sed -i "s|{{WEB_ROOT}}|${_v}|" /etc/apache2/sites-enabled/000-default.conf
fi
if [ -n "${SERVER_NAME:-}" ]; then
  _v=$(_escape_sed "${SERVER_NAME}"); sed -i "s|{{SERVER_NAME}}|${_v}|" /etc/apache2/sites-enabled/000-default.conf
fi
# Replace // by /.
sed -i "s/\/\//\//g" /etc/apache2/sites-enabled/000-default.conf

# Ensure the code-server user-data and extensions directories exist and are owned by the target user.
mkdir -p "$CODES_USER_DATA_DIR/extensions"
chown "${SUDO_USER:-$USER}:" "$CODES_USER_DATA_DIR" "$CODES_USER_DATA_DIR/extensions"

# Install any custom packages.
# If a user-provided installer exists, run it in a separate bash process so
# any `set -e`/`set -u`/traps cannot terminate this startup script, then
# import only the exported environment it produced.
if [ -f "$APP_ROOT/.devpanel/custom_package_installer.sh" ]; then
  _installer_env_file=$(mktemp)
  _installer_rc_file=$(mktemp)
  chmod 600 "$_installer_env_file" "$_installer_rc_file"
  bash -c '
    _installer_path=$1
    _env_file=$2
    _rc_file=$3

    trap '"'"'
      _rc=$?
      trap - EXIT
      printf "%s\n" "$_rc" > "$_rc_file"
      export -p > "$_env_file"
      exit 0
    '"'"' EXIT

    set +e +u +o pipefail 2>/dev/null || true
    shopt -s expand_aliases
    alias exit="return"
    # SC1090/SC1091: intentional dynamic source of a user file
    # shellcheck disable=SC1090,SC1091
    . "$_installer_path"
    _installer_rc=$?
    unalias exit 2>/dev/null || true
    exit "$_installer_rc"
  ' bash "$APP_ROOT/.devpanel/custom_package_installer.sh" \
    "$_installer_env_file" "$_installer_rc_file" \
    >> /tmp/custom_package_installer.log 2>&1 || true

  if [ -f "$_installer_env_file" ]; then
    # Import only the environment exported by the child shell.
    # shellcheck disable=SC1090
    . "$_installer_env_file"
  fi

  _installer_rc=0
  if [ -s "$_installer_rc_file" ]; then
    read -r _installer_rc < "$_installer_rc_file" || true
  fi
  if [ "${_installer_rc:-0}" -ne 0 ]; then
    printf "custom_package_installer.sh exited with code %s (continuing startup)\n" \
      "$_installer_rc" >> /tmp/custom_package_installer.log
  fi

  rm -f "$_installer_env_file" "$_installer_rc_file"
fi

set -m
if [[ "$CODES_ENABLE" == "yes" ]]; then
  # Install the GitHub Copilot Chat extension and any user-specified VSCode extensions.
  if [ -z "$(find "$CODES_USER_DATA_DIR/extensions/" -maxdepth 1 -iname 'github.copilot-chat-*' -type d 2>/dev/null)" ]; then
    sudo -u "${SUDO_USER:-$USER}" -E -- code-server --install-extension /usr/local/share/devpanel/copilot-chat.vsix --user-data-dir="$CODES_USER_DATA_DIR"
  fi
  if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
    IFS=',' read -ra _dp_extensions <<< "$DP_VSCODE_EXTENSIONS"
    for value in "${_dp_extensions[@]}"; do
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      [ -z "$value" ] && continue
      _ext_id="${value%%@*}"
      if [ -z "$(find "$CODES_USER_DATA_DIR/extensions/" -maxdepth 1 -iname "${_ext_id}-*" -type d 2>/dev/null)" ]; then
        sudo -u "${SUDO_USER:-$USER}" -E -- code-server --install-extension "$value" --user-data-dir="$CODES_USER_DATA_DIR"
      fi
    done
  fi

  # Start the primary process and put it in the background.
  apache2-foreground &
  # Start the helper process.
  if [[ "$CODES_AUTH" == "yes" ]]; then
    sudo -u "${SUDO_USER:-$USER}" -E -- code-server --port "$CODES_PORT" --host 0.0.0.0 "$CODES_WORKING_DIR" --user-data-dir="$CODES_USER_DATA_DIR"
  else
    sudo -u "${SUDO_USER:-$USER}" -E -- code-server --auth none --port "$CODES_PORT" --host 0.0.0.0 "$CODES_WORKING_DIR" --user-data-dir="$CODES_USER_DATA_DIR"
  fi
  # Now bring it to the foreground.
  fg %1
else
  # Start the primary process.
  apache2-foreground
fi
