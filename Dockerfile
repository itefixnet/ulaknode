# syntax=docker/dockerfile:1
# Base
FROM debian:stable-slim

# Install
RUN apt-get update && apt-get -y install --no-install-recommends \
    curl sudo dnsutils \
    netcat-openbsd iproute2 socat \
    postfix dovecot-imapd dovecot-lmtpd \
    rspamd redis clamav clamav-daemon \
    libsasl2-modules lsb-release ca-certificates  && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create a shared group with service members
RUN groupadd --system ulaknode-mail && \
    usermod -a -G ulaknode-mail postfix && \
    usermod -a -G ulaknode-mail dovecot && \
    usermod -a -G ulaknode-mail _rspamd && \
    usermod -a -G ulaknode-mail clamav && \
    usermod -a -G clamav _rspamd

# Copy configurations into default locations
COPY postfix/conf/   /etc/postfix/
COPY dovecot/conf/   /etc/dovecot/
COPY rspamd/         /etc/rspamd/
COPY clamav/clamd.conf /etc/clamav/clamd.conf

# Seed copies — used to populate fresh volumes
COPY postfix/conf/   /etc/postfix.defaults/
COPY dovecot/conf/   /etc/dovecot.defaults/
COPY rspamd/         /etc/rspamd.defaults/

# Copy scripts
COPY scripts/* /usr/local/bin/
RUN chmod 755 /usr/local/bin/*

# Create runtime directories
RUN mkdir -p /run/rspamd /run/clamav /run/redis && \
    chown -R _rspamd:_rspamd /run/rspamd && \
    chown -R clamav:clamav /run/clamav

# Create DKIM key store
RUN mkdir -p /etc/rspamd/dkim /etc/rspamd.defaults/dkim && \
    chown -R _rspamd:_rspamd /etc/rspamd/dkim /etc/rspamd.defaults/dkim && \
    chmod 750 /etc/rspamd/dkim /etc/rspamd.defaults/dkim

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose mail ports
EXPOSE 25 587 993

HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD postfix status && dovecot status && socat /dev/null TCP4:127.0.0.1:11332,timeout=2 && socat /dev/null TCP4:127.0.0.1:6379,timeout=2 || exit 1

# Persistent volumes
VOLUME ["/var/mail", "/var/log", "/etc/postfix", "/etc/dovecot", "/etc/rspamd", "/etc/ssl/mail"]

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/docker-init"]
