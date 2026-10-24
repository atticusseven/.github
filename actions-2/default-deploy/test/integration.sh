#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
prefix="default-deploy-test-$$"
network="$prefix-network"
volume="$prefix-wordpress"
database="$prefix-db"
wordpress="$prefix-cli"

cleanup() {
  local status=$?
  docker rm -f "$wordpress" "$database" >/dev/null || status=1
  docker volume rm "$volume" >/dev/null || status=1
  docker network rm "$network" >/dev/null || status=1
  exit "$status"
}
trap cleanup EXIT

# No host ports, host files, production configuration or production credentials.
docker network create "$network" >/dev/null
docker volume create "$volume" >/dev/null
docker run -d --name "$database" --network "$network" \
  -e MARIADB_ROOT_PASSWORD=isolated-test-root \
  -e MARIADB_DATABASE=wordpress \
  -e MARIADB_USER=wordpress \
  -e MARIADB_PASSWORD=isolated-test-only \
  mariadb:11.4 >/dev/null
docker run -d --name "$wordpress" --network "$network" --user 0 \
  -v "$volume:/var/www/html" --entrypoint sh \
  wordpress:cli-php8.3 -c 'while :; do sleep 3600; done' >/dev/null
docker exec "$wordpress" sh -c \
  'printf "memory_limit=512M\n" > /usr/local/etc/php/conf.d/deployment-test.ini'

ready=false
for attempt in {1..60}; do
  if docker exec "$database" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  docker logs "$database"
  echo "Isolated test database did not become ready" >&2
  exit 1
fi

wp() {
  docker exec "$wordpress" wp --allow-root "$@"
}
wp core download --version=6.8.3
wp config create --dbname=wordpress --dbuser=wordpress \
  --dbpass=isolated-test-only --dbhost="$database"
wp core install --url=http://wordpress.invalid --title="Isolated deployment test" \
  --admin_user=test --admin_password=isolated-test-only --admin_email=test@example.invalid \
  --skip-email
wp --info

docker exec -i "$wordpress" sh <<'SH'
set -eu
rm -f wp-content/plugins/hello.php
rm -rf wp-content/plugins/akismet
for plugin in already-active unrelated-inactive disable-emails password-protected; do
  mkdir -p "wp-content/plugins/$plugin"
  printf '<?php\n/* Plugin Name: %s */\n' "$plugin" > "wp-content/plugins/$plugin/$plugin.php"
done
for type in events projects resources; do
  mkdir -p "wp-content/plugins/a7-$type"
  cat > "wp-content/plugins/a7-$type/a7-$type.php" <<PHP
<?php
/* Plugin Name: Test $type */
add_action('init', function () {
    register_post_type('$type', ['public' => true, 'has_archive' => true]);
});
register_activation_hook(__FILE__, function () {
    \$order = get_option('deployment_test_activation_order', []);
    \$order[] = '$type';
    update_option('deployment_test_activation_order', \$order);
});
PHP
done
cat >> wp-content/plugins/a7-projects/a7-projects.php <<'PHP'
add_action('init', function () {
    register_taxonomy('project-type', 'projects', ['public' => true]);
});
PHP
mkdir -p wp-content/themes/deployment-test
printf '/* Theme Name: Deployment Test */\n' > wp-content/themes/deployment-test/style.css
printf '<?php\n' > wp-content/themes/deployment-test/index.php
cat > wp-content/themes/deployment-test/functions.php <<'PHP'
<?php
add_action('init', function () {
    register_post_type('theme-items', ['public' => true, 'has_archive' => true]);
});
PHP
SH
wp theme activate deployment-test
wp plugin activate already-active
WP_TEST_CONTAINER="$wordpress" ruby deploy_test.rb
