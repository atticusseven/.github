cd ~
echo 'dumping prod db to ~/production_temp.sql...'
cd ~/public_html
wp db export ~/production_temp.sql

cd ~/dev
echo 'cleaning dev DB and importing production dump...'
wp db clean
wp db import ~/production_temp.sql

echo 'String replaces...'
wp search-replace vandme.co.uk dev.vandme.co.uk

echo 'patching for dev'
wp option patch update woocommerce_stripe_settings testmode yes
wp plugin install disable-emails --skip-plugins --skip-themes
wp plugin activate disable-emails --skip-plugins --skip-themes

echo 'file sync... & cleanup'
rsync -avP --exclude=wp-config.php --delete-after ~/public_html/ ~/dev
rm ~/production_temp.sql
wp cache flush

echo 'dev sync complete...'