#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1
SSH_USER=$2
SSH_HOST=$3
SSH_DESTINATION_DIR=$4

wp_cli_default_params="--path=html/wp --skip-plugins --skip-themes --ssh=${SSH_USER}@${SSH_HOST}:${SSH_DESTINATION_DIR}"

#free plugins need installing and activating
plugins=`cat "${PLUGINS_JSON_FILE}" | json`

#existing plugins
live_plugins=`wp plugin list --field=name --status=active,inactive "${wp_cli_default_params}"`


activate_plugin() {
  plugin=$1
  if ! wp plugin is-active "${plugin}" "${wp_cli_default_params}" ; then
      echo " * Activating the ${plugin} plugin"
      wp plugin activate "${plugin}" "${wp_cli_default_params}"
  else
    echo " * The ${plugin} plugin is already active."
  fi
}

install_plugin() {
  plugin=$1
  if wp plugin is-installed "${plugin}" "${wp_cli_default_params}" ; then
    echo " * The ${plugin} plugin is already installed."
    wp plugin update "${plugin}" "${wp_cli_default_params}"
    activate_plugin "${plugin}"
  else
    echo " * Installing and activating plugin: '${plugin}'"
    wp plugin install "${plugin}" --activate "${wp_cli_default_params}"
  fi
}

install_activate_premium_plugin() {
    plugin=$1
    #always overwite to ensure the correct version is installed
    echo " * Installing and activating the ${plugin} plugin"
    wp plugin install premium-plugins/"${plugin}".zip --activate --force "${wp_cli_default_params}"
}

maybe_delete_plugin() {
  #use npm json to filter array by $plugin and see if the array length is 0
  live_plugin=$1
  plugins=`cat "${PLUGINS_JSON_FILE}" | json -c "this.name == '${live_plugin}'"`
  #echo "${plugins}"
  match=$(echo "${plugins}" | jq length)
  #echo "${match}"
  if [[ "${match}" -lt 1 ]]
    then
        #if it a live plugin is not in our defined plugin list, then deactivate it and delete it
        echo " * Deactivating the ${live_plugin} plugin"
        wp plugin deactivate "${plugin}" "${wp_cli_default_params}"
        echo " * Deleting the ${plugin} plugin"
        php wp-cli.phar plugin delete "${plugin}" "${wp_cli_default_params}"
  fi

}

for k in $(jq '. | keys | .[]' <<< "$live_plugins"); do
    plugin=$(jq -r ".[$k]" <<< "$live_plugins");
    maybe_delete_plugin "${plugin}"
    #echo "${plugin}"
done

for k in $(jq '. | keys | .[]' <<< "$plugins"); do
    plugin=$(jq -r ".[$k].name" <<< "$plugins");
    type=$(jq -r ".[$k].type" <<< "$plugins");
    if [ "${type}" == "free" ]; then
        install_plugin "${plugin}"
    elif [ "${type}" == "custom" ] || [ "${type}" == "composer" ]; then
        activate_plugin "${plugin}"
    elif [ "${type}" == "premium" ]; then
        install_activate_premium_plugin "${plugin}"
    else
        echo "Unknown Plugin Type"
    fi
done

#clean up
# remove premium plugins directory from destination server
ssh -i /home/runner/.ssh/github_actions "${SSH_USER}"@"${SSH_HOST}" "rm -rf ${SSH_DESTINATION_DIR}/premium-plugins"







