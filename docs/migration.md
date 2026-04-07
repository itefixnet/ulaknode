# Migrating existing mailboxes to ulaknode

This guide covers migrating Dovecot mailboxes from an existing mail server into ulaknode.

---

## Overview

Dovecot stores mail in Maildir format — plain files that can be copied directly.

The process:
1. Stop delivery on the old server
2. Rsync maildirs into the Docker volume
3. Register accounts in ulaknode
4. Fix ownership
5. Cut over DNS

---

## Path mapping

The container expects maildirs at `/var/mail/<domain>/<user>/`.

If your existing setup uses a different layout (e.g. `/var/mail/vmail/<user>@<domain>/` or `/home/<user>/Maildir/`) you need to remap during the copy — see the examples below.

---

## Step-by-step

**1. Stop incoming delivery on the old server** (prevents new mail arriving mid-copy)

```bash
# Pause Postfix so the queue drains but no new mail is accepted
postconf -e "inet_interfaces = loopback-only"
systemctl reload postfix
```

**2. Copy maildirs into the Docker volume**

The Docker volume `ulak_mail` is accessible on the host at `/var/lib/docker/volumes/ulak_mail/_data`.

```bash
# Existing layout: /var/mail/vmail/user@domain/ on old server
rsync -av --progress \
  oldserver:/var/mail/vmail/user@yourdomain.com/ \
  /var/lib/docker/volumes/ulak_mail/_data/yourdomain.com/user/
```

For a whole domain at once:

```bash
DOMAIN=yourdomain.com
SRC_ROOT=oldserver:/var/mail/vmail

for user in alice bob postmaster; do
  rsync -av --progress \
    "$SRC_ROOT/${user}@${DOMAIN}/" \
    "/var/lib/docker/volumes/ulak_mail/_data/${DOMAIN}/${user}/"
done
```

If your existing layout is already `domain/user/`, a single rsync suffices:

```bash
rsync -av --progress oldserver:/var/mail/ \
  /var/lib/docker/volumes/ulak_mail/_data/
```

**3. Fix ownership**

The container runs Dovecot as UID/GID 5000:

```bash
chown -R 5000:5000 /var/lib/docker/volumes/ulak_mail/_data/
```

**4. Register accounts in ulaknode**

```bash
# Option A — set a new password
docker exec ulaknode ulaknode-domain add yourdomain.com
docker exec ulaknode ulaknode-mailbox add alice@yourdomain.com newpassword

# Option B — insert an existing SHA512-CRYPT hash directly (no password reset needed)
HASH='{SHA512-CRYPT}$6$...'   # paste hash from old passwd file
docker exec ulaknode sqlite3 /var/lib/sqlite/vmail.db \
  "INSERT INTO virtual_users (domain_id, email, password, maildir)
   SELECT id, 'alice@yourdomain.com', '$HASH', '/var/mail/yourdomain.com/alice'
   FROM virtual_domains WHERE name='yourdomain.com';"
```

**5. Verify inside the container**

```bash
docker exec ulaknode ulaknode-domain show yourdomain.com
docker exec ulaknode ls /var/mail/yourdomain.com/
```

**6. Cut over DNS**

Update the MX record for your domain to point to the new server. Lower the TTL in advance (e.g. to 300s) so the change propagates quickly.

**7. Re-enable Postfix on the old server** (optional fallback during TTL drain)

```bash
postconf -e "inet_interfaces = all"
systemctl reload postfix
```

Once the TTL has expired and no new mail is arriving at the old server, the migration is complete.

---

## Notes

- **Dovecot index files** (`dovecot.index`, `dovecot.index.cache`) are safe to copy — Dovecot rebuilds them automatically if missing or incompatible.
- **Subscriptions** — the `subscriptions` file inside each Maildir root is plain text and copies cleanly.
- **Quota accounting** — if the old server used Maildir++ quota (`.maildirsize` files), those transfer with rsync. Set the quota afterwards: `ulaknode-mailbox quota-set alice@yourdomain.com 2G`.
- **Second rsync pass** — run rsync again with `--delete` just before DNS cutover to pick up any mail that arrived after the first copy.

---

## Ops notes

**Port 25 blocked** — most cloud providers (AWS, GCP, Azure, Hetzner) block outbound TCP/25 by default. Request it unblocked or configure a smarthost relay (`relayhost` in Postfix config).

**Firewall** — open required ports:

```bash
ufw allow 25,587,993/tcp
```

**Reverse DNS** — set your server's PTR record to `mail.yourdomain.com`. Many receiving servers reject mail from IPs without a matching rDNS entry.

**ClamAV first run** — the virus database download takes a few minutes on first start. Wait before testing delivery:

```bash
docker exec ulaknode ulaknode-errlog freshclam
```

**certbot renewal** — add a cron job or systemd timer to renew and reinstall the certificate:

```bash
certbot renew --quiet && \
  docker exec ulaknode ulaknode-cert install \
    /etc/letsencrypt/live/mail.yourdomain.com/fullchain.pem \
    /etc/letsencrypt/live/mail.yourdomain.com/privkey.pem && \
  docker exec ulaknode ulaknode-service restart postfix && \
  docker exec ulaknode ulaknode-service restart dovecot
```
