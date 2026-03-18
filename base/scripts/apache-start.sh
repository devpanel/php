#!/bin/bash
# Turn on bash's job control.

cp /templates/apache2.conf /etc/apache2/apache2.conf
cp /templates/000-default.conf /etc/apache2/sites-enabled/000-default.conf
cp /templates/php.ini ${PHP_EXT_DIR}/zz-www.ini

# Substitute in php.ini values.
[ ! -z "${PHP_CLEAR_ENV}" ] && sed -i "s|{{PHP_CLEAR_ENV}}|${PHP_CLEAR_ENV}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MEMORY_LIMIT}" ] && sed -i "s|{{PHP_MEMORY_LIMIT}}|${PHP_MEMORY_LIMIT}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_UPLOAD_MAX_FILESIZE}" ] && sed -i "s|{{PHP_UPLOAD_MAX_FILESIZE}}|${PHP_UPLOAD_MAX_FILESIZE}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_POST_MAX_SIZE}" ] && sed -i "s|{{PHP_POST_MAX_SIZE}}|${PHP_POST_MAX_SIZE}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_EXECUTION_TIME}" ] && sed -i "s|{{PHP_MAX_EXECUTION_TIME}}|${PHP_MAX_EXECUTION_TIME}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_INPUT_TIME}" ] && sed -i "s|{{PHP_MAX_INPUT_TIME}}|${PHP_MAX_INPUT_TIME}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_INPUT_VARS}" ] && sed -i "s|{{PHP_MAX_INPUT_VARS}}|${PHP_MAX_INPUT_VARS}|" ${PHP_EXT_DIR}/zz-www.ini

# Add custom php.ini if it exists.
[ -f "$PHP_CUSTOM_INI" ] && cp $PHP_CUSTOM_INI ${PHP_EXT_DIR}/zzz-www-custom.ini

# Custom Environment variables in /etc/apache2/sites-enabled/000-default.conf.
[ ! -z "$APP_ROOT" ] && sed -i "s|{{APP_ROOT}}|${APP_ROOT}|" /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$WEB_ROOT" ] && sed -i "s|{{WEB_ROOT}}|${WEB_ROOT}|" /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$SERVER_NAME" ] && sed -i "s|{{SERVER_NAME}}|${SERVER_NAME}|" /etc/apache2/sites-enabled/000-default.conf
# Replace // by /.
sed -i "s/\/\//\//g" /etc/apache2/sites-enabled/000-default.conf

# install Drush 7, 8, 9, 10, 11.
/bin/bash source ~/.bashrc

# Install any custom packages.
[ -f "$APP_ROOT/.devpanel/custom_package_installer.sh" ] && /bin/bash $APP_ROOT/.devpanel/custom_package_installer.sh  >> /tmp/custom_package_installer.log

set -m
if [[ "$CODES_ENABLE" == "yes" ]]; then
  # Install the GitHub Copilot Chat extension and any user-specified VSCode extensions.
  sudo -u "$USER" -E -- code-server --install-extension /usr/local/share/devpanel/copilot-chat.vsix
  if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
    IFS=',' read -ra _dp_extensions <<< "$DP_VSCODE_EXTENSIONS"
    for value in "${_dp_extensions[@]}"; do
      sudo -u "$USER" -E -- code-server --install-extension "$value"
    done
  fi

  # Start the primary process and put it in the background.
  apache2-foreground &
  # Start the helper process.
  if [[ "$CODES_AUTH" == "yes" ]]; then
    sudo -u "$USER" -E -- code-server --port $CODES_PORT --host 0.0.0.0 $CODES_WORKING_DIR
  else
    sudo -u "$USER" -E -- code-server --auth none --port $CODES_PORT --host 0.0.0.0 $CODES_WORKING_DIR
  fi
  # Now bring it to the foreground.
  fg %1
else
  # Start the primary process.
  apache2-foreground
fi
