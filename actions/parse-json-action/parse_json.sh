#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1

cat "${PLUGINS_JSON_FILE}" | json -c 'this.type == "composer"'


