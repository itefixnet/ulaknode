#!/bin/bash
set -e

DB_PATH="/var/lib/drupal/db.sqlite"
WWW_PATH="/var/www/html"
SETTINGS_FILE="$WWW_PATH/web/sites/default/settings.php"
FILES_DIR="$WWW_PATH/web/sites/default/files"

# Defaults
: "${ULAKNODE_DRUPAL_SITE_NAME:=Ulaknode}"

# Validate credentials
if [ -z "$ULAKNODE_DRUPAL_ADMIN_USER" ] || [ -z "$ULAKNODE_DRUPAL_ADMIN_PASSWORD" ]; then
  echo "ERROR: ULAKNODE_DRUPAL_ADMIN_USER and ULAKNODE_DRUPAL_ADMIN_PASSWORD must be set (use -e or --env-file)."
  exit 1
fi

# -------------------------------------------------------------
# Prepare SQLite database and settings.php if missing
# -------------------------------------------------------------
echo "Preparing Drupal settings and SQLite database..."
mkdir -p "$(dirname "$DB_PATH")"
touch "$DB_PATH"
chown www-data:www-data "$DB_PATH"

if [ ! -f "$SETTINGS_FILE" ]; then
  cp "$WWW_PATH/web/sites/default/default.settings.php" "$SETTINGS_FILE"
  chown www-data:www-data "$SETTINGS_FILE"
  echo "" >> "$SETTINGS_FILE"
  echo "\$databases['default']['default'] = [" >> "$SETTINGS_FILE"
  echo "  'driver' => 'sqlite'," >> "$SETTINGS_FILE"
  echo "  'database' => '$DB_PATH'," >> "$SETTINGS_FILE"
  echo "];" >> "$SETTINGS_FILE"
fi

mkdir -p "$FILES_DIR"
chown -R www-data:www-data "$FILES_DIR"

# -------------------------------------------------------------
# Initialize Drupal if DB is empty
# -------------------------------------------------------------
cd "$WWW_PATH"

if ! drush status --field=bootstrap | grep -q "Successful"; then
  echo "Installing Drupal automatically..."
  drush site:install minimal \
    --db-url=sqlite://localhost/$DB_PATH \
    --account-name="$ULAKNODE_DRUPAL_ADMIN_USER" \
    --account-pass="$ULAKNODE_DRUPAL_ADMIN_PASSWORD" \
    --site-name="$ULAKNODE_DRUPAL_SITE_NAME" \
    --yes
  chown -R www-data:www-data "$WWW_PATH"

  drush theme:enable olivero -y
  drush config:set system.theme default olivero -y

  # additional core modules to enable
  drush en field text options field_ui -y

  # Install Ulaknode Drupal modules
  drush en -y ulaknode_status \
    ulaknode_vmail \
    ulaknode_postfix \
    ulaknode_dovecot \
    ulaknode_rspamd \
    ulaknode_rspamd_dkim_signing \
    ulaknode_rspamd_clamav \
    ulaknode_menu \
    ulaknode_config
  
  drush updb -y
  drush cr

else
  echo "Drupal already installed — skipping installation."
fi

# -------------------------------------------------------------
# Import configuration if available
# -------------------------------------------------------------
CONFIG_SYNC_DIR="$WWW_PATH/config/sync"

if [ -d "$CONFIG_SYNC_DIR" ]; then
  echo "Found configuration directory at $CONFIG_SYNC_DIR"
  if drush status --field=bootstrap | grep -q "Successful"; then
    echo "Importing Drupal configuration..."
    drush config:import --yes || echo "Config import failed or not applicable."
  else
    echo "Skipping config import — Drupal not bootstrapped yet."
  fi
else
  echo "No configuration directory found — skipping import."
fi

# -------------------------------------------------------------
# Add reverse proxy configuration if requested
# -------------------------------------------------------------
if [ -n "$ULAKNODE_REVERSE_PROXY_IP" ]; then
  echo "Configuring Drupal reverse proxy for $ULAKNODE_REVERSE_PROXY_IP ..."
  {
    echo ""
    echo "/** Reverse proxy configuration **/"
    echo "\$settings['reverse_proxy'] = TRUE;"
    echo "\$settings['reverse_proxy_addresses'] = ['${ULAKNODE_REVERSE_PROXY_IP}'];"
    echo "\$settings['reverse_proxy_header'] = 'X-Forwarded-For';"
    echo "if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {"
    echo "  \$_SERVER['HTTPS'] = 'on';"
    echo "}"
  } >> "$SETTINGS_FILE"
  chown www-data:www-data "$SETTINGS_FILE"
fi

# -------------------------------------------------------------
# Prepare active configurations for mail services and set permissions
# -------------------------------------------------------------
/usr/local/bin/generate-postfix-conf
/usr/local/bin/generate-dovecot-conf
/usr/local/bin/generate-rspamd-conf
/usr/local/bin/set-conf-permissions

# -------------------------------------------------------------
# Start main process
# -------------------------------------------------------------
echo "Starting Supervisor..."
exec "$@"
