#!/bin/bash

DOMAIN=$1
SUB_DOMAIN=$2
WP_ENV=$3
PROJECT=$4
DB_NAME=$5
REDIS_DATABASES=$6

redis_databases=`echo "${REDIS_DATABASES}" | json`
env_redis_db=$(jq -r ".$WP_ENV" <<< "${redis_databases}");

project_root_domain="${DOMAIN}"

#Do NOT use the WWW subdomain on the site_domain (reserved for production env)
if [[ "$SUB_DOMAIN" != "www" && "$SUB_DOMAIN" != "" ]]; then
    site_domain="${SUB_DOMAIN}.${DOMAIN}"
else
    site_domain="${DOMAIN}"
fi

# Prepend env subdomains

if [[ "$WP_ENV" == "dev" || "$WP_ENV" == "staging" ]]; then
    env="${WP_ENV}"
elif [[ "$WP_ENV" == "production" ]]; then
    if [[ "$SUB_DOMAIN" == "www" || "$SUB_DOMAIN" == "" ]]; then
        env="${SUB_DOMAIN}"
    else
        env=""
    fi
fi

if [[ $env == "" ]]; then #no leading dot
    env_domain="${site_domain}"
    env_root_domain="${project_root_domain}"
else
    env_domain="${env}.${site_domain}"
    env_root_domain="${env}.${project_root_domain}"
fi

env_db_name="${DB_NAME}_${env}"

#mnt/falo/sites/dev/dev.findalondonoffice.co.uk
env_path="/mnt/$PROJECT/sites/$WP_ENV/$env_domain"

echo "env_domain=${env_domain}"
echo "env_root_domain=${env_root_domain}"
echo "project_root_domain=${project_root_domain}"
echo "env_path=${env_path}"
echo "env_redis_db=${env_redis_db}"
echo "env_db_name=${env_db_name}"
