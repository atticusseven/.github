cd ~
echo 'dumping prod db to ~/production_temp.sql...'
cd ~/public_html
wp db export ~/production_temp.sql

cd ~/staging
echo 'cleaning staging DB and importing production dump...'
wp db clean
wp db import ~/production_temp.sql

echo 'String replaces...'
wp search-replace vandme.co.uk staging.vandme.co.uk

echo 'patching for staging'
wp option patch update woocommerce_stripe_settings testmode yes
wp plugin install disable-emails --skip-plugins --skip-themes
wp plugin activate disable-emails --skip-plugins --skip-themes

echo 'file sync... & cleanup'
rsync -avP --exclude=wp-config.php --delete-after ~/public_html/ ~/staging
rm ~/production_temp.sql
wp cache flush

echo 'staging sync complete...'