#!/usr/bin/env bash

PLUGINS_JSON_FILE=$1


json=$(<"${PLUGINS_JSON_FILE}")  
echo json | json -c 'this.type = "composer"'


