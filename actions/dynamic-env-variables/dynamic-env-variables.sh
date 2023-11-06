#!/bin/bash

DOMAIN=$1
WP_ENV=$2
PROJECT=$3
DB_NAME=$4
REDIS_DATABASES=$5

redis_databases=`echo "${REDIS_DATABASES}" | json`
env_redis_db=$(jq -r ".$WP_ENV" <<< "${redis_databases}");

if [[ "$WP_ENV" == "dev" ]]; then
    env_domain="dev.${DOMAIN}"
    env_db_name="${DB_NAME}_dev"
elif [[ "$WP_ENV" == "staging" ]]; then
    env_domain="staging.${DOMAIN}"
    env_db_name="${DB_NAME}_staging"
elif [[ "$WP_ENV" == "production" ]]; then
    env_domain="www.${DOMAIN}"
    env_db_name="${DB_NAME}"
else
    env_domain="undefined"
    env_db_name="undefined"
fi

#mnt/falo/sites/dev/dev.findalondonoffice.co.uk
env_path="/mnt/$PROJECT/sites/$WP_ENV/$env_domain"

echo "env_domain=${env_domain}"#
echo "env_path=${env_path}"
echo "env_redis_db=${env_redis_db}"
echo "env_db_name=${env_db_name}"
