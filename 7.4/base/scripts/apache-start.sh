#!/bin/bash
# Turn on bash's job control

sudo cp /templates/apache2.conf /etc/apache2/apache2.conf
sudo cp /templates/000-default.conf /etc/apache2/sites-enabled/000-default.conf
sudo cp /templates/php.ini ${PHP_EXT_DIR}/zz-www.ini

# Substitute in php.ini values
[ ! -z "${PHP_CLEAR_ENV}" ] && sed -i "s|{{PHP_CLEAR_ENV}}|${PHP_CLEAR_ENV}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MEMORY_LIMIT}" ] && sed -i "s|{{PHP_MEMORY_LIMIT}}|${PHP_MEMORY_LIMIT}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_UPLOAD_MAX_FILESIZE}" ] && sed -i "s|{{PHP_UPLOAD_MAX_FILESIZE}}|${PHP_UPLOAD_MAX_FILESIZE}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_POST_MAX_SIZE}" ] && sed -i "s|{{PHP_POST_MAX_SIZE}}|${PHP_POST_MAX_SIZE}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_EXECUTION_TIME}" ] && sed -i "s|{{PHP_MAX_EXECUTION_TIME}}|${PHP_MAX_EXECUTION_TIME}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_INPUT_TIME}" ] && sed -i "s|{{PHP_MAX_INPUT_TIME}}|${PHP_MAX_INPUT_TIME}|" ${PHP_EXT_DIR}/zz-www.ini
[ ! -z "${PHP_MAX_INPUT_VARS}" ] && sed -i "s|{{PHP_MAX_INPUT_VARS}}|${PHP_MAX_INPUT_VARS}|" ${PHP_EXT_DIR}/zz-www.ini

# Add custom php.ini if it exists
[ -f "$PHP_CUSTOM_INI" ] && sudo cp $PHP_CUSTOM_INI ${PHP_EXT_DIR}/zzz-www-custom.ini

# Custom Environment variables in /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$APP_ROOT" ] &&  sudo sed -i "s|{{APP_ROOT}}|${APP_ROOT}|" /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$WEB_ROOT" ] &&  sudo sed -i "s|{{WEB_ROOT}}|${WEB_ROOT}|" /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$SERVER_NAME" ] && sudo sed -i "s|{{SERVER_NAME}}|${SERVER_NAME}|" /etc/apache2/sites-enabled/000-default.conf
# Replace // by /
sudo sed -i "s/\/\//\//g" /etc/apache2/sites-enabled/000-default.conf

# Custom Environment variable in /etc/apache2/apache2.conf
[ ! -z "$WEB_ROOT" ] && sudo sed -i "s|{{WEB_ROOT}}|${WEB_ROOT}|" /etc/apache2/apache2.conf

# install Drush 7, 8, 9, 10, 11
/bin/bash source ~/.bashrc

# Configure code server
if [[ ! -d "$CODES_USER_DATA_DIR" ]]; then
  mkdir -p $CODES_USER_DATA_DIR
  sudo chown -R www:www $CODES_USER_DATA_DIR
fi

set -m
if [[ "$CODES_ENABLE" == "yes" ]]; then
# Start the primary process and put it in the background
sudo -E apache2-foreground &
# Start the helper process
if [[ "$CODES_AUTH" == "yes" ]]; then
sudo -u www -E -- code-server --port $CODES_PORT --host 0.0.0.0 $CODES_WORKING_DIR --user-data-dir=$CODES_USER_DATA_DIR
else
sudo -u www -E -- code-server --auth none --port $CODES_PORT --host 0.0.0.0 $CODES_WORKING_DIR --user-data-dir=$CODES_USER_DATA_DIR
fi
# and leave it there
fg %1
else
# Start the primary process and put it in the background
sudo -E apache2-foreground
fi

# Install custom packages if have
[ -f "$APP_ROOT/.devpanel/custom_package_installer.sh" ] && /bin/bash $APP_ROOT/.devpanel/custom_package_installer.sh  >> /tmp/custom_package_installer.log
