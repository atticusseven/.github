#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1
SSH_DESTINATION_DIR=$2

wp_cli_default_params="--skip-plugins --skip-themes --ssh=server:${SSH_DESTINATION_DIR}/html/wp"

#echo "${wp_cli_default_params}"
#wp --info
wp plugin list --skip-plugins --skip-themes --ssh=server:"${SSH_DESTINATION_DIR}"/html/wp







