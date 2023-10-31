#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1
SSH_USER=$2
SSH_HOST=$3
SSH_DESTINATION_DIR=$4

wp_cli_default_params="--skip-plugins --skip-themes --ssh=${SSH_USER}@${SSH_HOST}:${SSH_DESTINATION_DIR}/html/wp"

wp plugin list "${wp_cli_default_params}"







