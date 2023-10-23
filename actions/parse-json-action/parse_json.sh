#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1

composer_plugins=`cat "${PLUGINS_JSON_FILE}" | json -c 'this.type == "composer"'`
echo "${composer_plugins}"


