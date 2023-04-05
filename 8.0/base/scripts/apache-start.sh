#!/bin/bash
# Turn on bash's job control

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
[ ! -z "$WEB_ROOT" ] &&  sudo sed -i "s|{{WEB_ROOT}}|${WEB_ROOT}|" /etc/apache2/sites-enabled/000-default.conf
[ ! -z "$SERVER_NAME" ] && sudo sed -i "s|{{SERVER_NAME}}|${SERVER_NAME}|" /etc/apache2/sites-enabled/000-default.conf

# install Drush 7, 8, 9, 10, 11
bash source ~/.bashrc

set -m
if [[ "$CODES_ENABLE" == "yes" ]]; then
# Start the primary process and put it in the background
sudo -E apache2-foreground &
# Start the helper process
sudo -u www -E -- code-server --auth none --port $CODES_PORT --host 0.0.0.0 $CODES_WORKING_DIR
# and leave it there
fg %1
else
# Start the primary process and put it in the background
sudo -E apache2-foreground
fi