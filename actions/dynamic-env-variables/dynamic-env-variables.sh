#!/bin/bash

DOMAIN=$1
WP_ENV=$2
PROJECT=$3
REDIS_DATABASES=$4

redis_databases=`echo "${REDIS_DATABASES}" | json`
env_redis_db=$(jq -r ".$WP_ENV" <<< "$redis_databases");

if [[ "$WP_ENV" == "dev" ]]; then
    env_domain="dev.${DOMAIN}"
elif [[ "$WP_ENV" == "staging" ]]; then
    env_domain="staging.${DOMAIN}"
elif [[ "$WP_ENV" == "production" ]]; then
    env_domain="www.${DOMAIN}"
else
    env_domain="undefined"
fi

#mnt/falo/sites/dev/dev.findalondonoffice.co.uk
env_path="/mnt/$PROJECT/sites/$WP_ENV/$env_domain"

echo "env_domain=https://${env_domain}"#
echo "env_path=${env_path}"
echo "env_redis_db=${env_redis_db}"
