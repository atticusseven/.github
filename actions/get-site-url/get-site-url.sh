DOMAIN=$1
WP_ENV=$2


if ["${WP_ENV}" = "dev"]; then
    site_url="https://dev.${DOMAIN}"
elif ["${WP_ENV}" = "staging"]; then
    site_url="https://staging.${DOMAIN}"
elif ["${WP_ENV}" = "production"]; then
    site_url="https://www.${DOMAIN}"]
else
    site_url="${WP_ENV}"
fi

echo "site-url=${site_url}"