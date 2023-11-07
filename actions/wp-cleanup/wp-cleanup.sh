#!/bin/bash

SSH_DESTINATION_DIR=$1

wp_cli_default_params="--skip-plugins --skip-themes --ssh=server:${SSH_DESTINATION_DIR}/html/wp"
    

  if echo wp plugin is-installed wp-rocket --skip-plugins --skip-themes --ssh=server:"${SSH_DESTINATION_DIR}/html/wp" | bash ; then
    wp package install wp-media/wp-rocket-cli:trunk
    echo wp rocket clean --confirm --ssh=server:"${SSH_DESTINATION_DIR}/html/wp" | bash
  fi