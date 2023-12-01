#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1
SSH_DESTINATION_DIR=$2

wp_cli_default_params="--skip-plugins --skip-themes --ssh=server${SSH_DESTINATION_DIR}/html/wp"

install_activate_premium_plugin() {
    plugin=$1
    #always overwite to ensure the correct version is installed
    echo " * Installing and activating the ${plugin} plugin"
    echo wp plugin install ../../premium-plugins/"${plugin}".zip --activate --force "${wp_cli_default_params}" | bash
}

#activate all plugins
echo wp plugin activate --all "${wp_cli_default_params}" | bash

#premium plugins need installing and activating
plugins=`cat "${PLUGINS_JSON_FILE}" | json`

for k in $(jq '. | keys | .[]' <<< "$plugins"); do
    plugin=$(jq -r ".[$k]" <<< "$plugins");
    install_activate_premium_plugin "${plugin}"
done

#clean up
# remove premium plugins directory from destination server
ssh server "rm -rf ${SSH_DESTINATION_DIR}/premium-plugins"

echo $?