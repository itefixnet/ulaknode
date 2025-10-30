# Base
FROM debian:stable-slim

ENV DRUPAL_DB_PATH=/var/lib/sqlite/drupal.db \
    DRUPAL_WWW_PATH=/var/www/html

# Install 
RUN apt-get update && apt-get -y install --no-install-recommends \
    apache2 sqlite3 curl supervisor fail2ban sudo \
    php php-dev php-bcmath php-intl php-soap php-zip php-curl \
    php-mbstring php-gd php-xml php-sqlite3 php-pdo libapache2-mod-php\
    composer postfix dovecot-imapd dovecot-lmtpd \
    rspamd clamav clamav-daemon \
    libsasl2-modules lsb-release ca-certificates  && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# create a shared group with service members
RUN groupadd --system ulaknode-mail && \
    usermod -a -G ulaknode-mail www-data && \
    usermod -a -G ulaknode-mail postfix && \
    usermod -a -G ulaknode-mail dovecot && \
    usermod -a -G ulaknode-mail _rspamd && \
    usermod -a -G ulaknode-mail clamav

# Copy and activate Drupal web site
COPY apache2/drupal.conf /etc/apache2/sites-available/drupal.conf
RUN a2dissite 000-default && \
    a2enmod rewrite headers env dir mime proxy proxy_http && \
    a2ensite drupal

# Install Drupal and Drush
RUN rm /var/www/html/index.html && \
    composer create-project drupal/recommended-project:11.2.5 "$DRUPAL_WWW_PATH" && \
    cd "$DRUPAL_WWW_PATH" && \
    composer require drush/drush && \
    ln -s "$DRUPAL_WWW_PATH/vendor/bin/drush" "/usr/local/bin/drush"

# Copy Ulaknode Drupal modules
COPY drupal/modules/ /var/www/html/web/modules/custom

# Create config directories
RUN mkdir -p /etc/ulaknode/postfix/managed/vmail \
    /etc/ulaknode/postfix/managed \
    /etc/ulaknode/postfix/user \
    /etc/ulaknode/postfix/active \
    /etc/ulaknode/dovecot/managed \
    /etc/ulaknode/dovecot/user \
    /etc/ulaknode/dovecot/active \
    /etc/ulaknode/vmail/managed \
    /etc/ulaknode/vmail/user \
    /etc/ulaknode/vmail/active \
    /etc/ulaknode/rspamd/managed \
    /etc/ulaknode/rspamd/active \
    /etc/ulaknode/rspamd/user

# Copy sudoers configuration
COPY sudoers/50-ulaknode-www-data /etc/sudoers.d/50-ulaknode-www-data
RUN chmod 440 /etc/sudoers.d/50-ulaknode-www-data

# Copy managed configurations
COPY postfix/conf /etc/ulaknode/postfix/managed/
COPY dovecot/conf /etc/ulaknode/dovecot/managed/

# Copy configuration scripts
COPY scripts/* /usr/local/bin/
RUN chmod 755 /usr/local/bin/*

# Copy rspamd configuration
COPY rspamd/ /etc/ulaknode/rspamd/managed/

# Create runtime directories
RUN mkdir -p /run/rspamd /run/clamav /var/run/fail2ban /var/lib/drupal && \
    chown -R www-data:www-data /var/lib/drupal && \
    chown -R _rspamd:_rspamd /run/rspamd && \
    chown -R clamav:clamav /run/clamav && \
    chmod 755 /var/run/fail2ban

# Copy supervisor and entrypoint script
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Download and install FileBrowser binary
COPY filebrowser /usr/local/bin/filebrowser
RUN chmod +x /usr/local/bin/filebrowser && \
    mkdir -p /var/lib/filebrowser && \
    chown -R root:ulaknode-mail /var/lib/filebrowser 

# Create database for virtual mail users
COPY sqlite3/vmail-schema.sql /etc/ulaknode/vmail/managed/vmail-schema.sql
RUN mkdir -p /var/lib/sqlite && \
    sqlite3 /var/lib/sqlite/vmail.db < /etc/ulaknode/vmail/managed/vmail-schema.sql && \
    chown -R root:ulaknode-mail /var/lib/sqlite/vmail.db && \
    chmod 660 /var/lib/sqlite/vmail.db

# Expose web + mail ports
EXPOSE 80 25 587 143 993

# Persistent volumes
VOLUME ["/var/www/html", "/var/lib/drupal", "/var/mail", "/var/log", "/var/lib/clamav"]

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
