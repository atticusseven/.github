#!/bin/bash

PLUGINS_JSON_FILE=$1
EXCLUDE_FILE=$2

#free plugins need installing and activating
plugins=`cat "${PLUGINS_JSON_FILE}" | json -c "this.type == 'free'"`

#echo "${plugins}"

grep -v '^$' "${EXCLUDE_FILE}" > temp.txt
rm "${EXCLUDE_FILE}"
mv temp.txt "${EXCLUDE_FILE}"

for k in $(jq '. | keys | .[]' <<< "$plugins"); do
    plugin=$(jq -r ".[$k].name" <<< "$plugins");
    echo "html/content/plugins/${plugin}" >> "${EXCLUDE_FILE}"
done