#!/usr/bin/env bash

SSH_DESTINATION_DIR=$1

wp_cli_default_params="--skip-plugins --skip-themes --ssh=server:${SSH_DESTINATION_DIR}/html/wp"

echo wp plugin list "${wp_cli_default_params}" | bash
echo $?