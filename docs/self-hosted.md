# Self-hosted deployment

This guide covers deploying Ulaknode on your own Linux server or VM.

---

## Requirements

- Linux server (Ubuntu 22.04+ or Debian 12+ recommended)
- 2+ vCPU, 4+ GB RAM, 40+ GB disk
- A public IP address you control
- A domain name with DNS management access
- Docker installed

---

## 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

---

## 2. Configure DNS

Before starting the container, set up DNS records for your domain:

| Record | Type | Value |
|---|---|---|
| `mail.yourdomain.com` | A | Your server's public IP |
| `yourdomain.com` | MX | `mail.yourdomain.com` (priority 10) |

PTR (reverse DNS) should also point your IP back to `mail.yourdomain.com`. This is configured through your hosting provider or ISP and is important for mail deliverability.

SPF, DKIM, and DMARC records should be added after the container is running (see step 6).

---

## 3. Open firewall ports

Allow inbound TCP on the following ports:

| Port | Protocol | Purpose |
|---|---|---|
| 25 | SMTP | Inbound mail from other servers |
| 587 | Submission | Outbound mail from mail clients |
| 993 | IMAPS | Mailbox access (TLS) |

> **Note:** Some ISPs and hosting providers block port 25 by default. Contact your provider to have it unblocked before proceeding.

---

## 4. Pull the image

The image is published on Docker Hub and pulled automatically via `docker compose`:

```bash
docker compose pull
```

Or pull manually:

```bash
docker pull itefixnet/ulaknode:latest
```

---

## 5. Run the container

Edit `docker-compose.yml` to set your mail hostname and TLS certificate paths:

```yaml
hostname: mail.yourdomain.com
environment:
  - MAIL_HOSTNAME=mail.yourdomain.com
volumes:
  - /etc/letsencrypt/live/mail.yourdomain.com/fullchain.pem:/run/certs/fullchain.pem:ro
  - /etc/letsencrypt/live/mail.yourdomain.com/privkey.pem:/run/certs/privkey.pem:ro
```

Then start:

```bash
docker compose up -d
```

---

## 6. Configure TLS

Copy your certificate files into the container, then install them with `ulaknode-cert`:

```bash
docker cp fullchain.pem ulaknode:/tmp/fullchain.pem
docker cp privkey.pem   ulaknode:/tmp/privkey.pem

docker exec ulaknode ulaknode-cert install /tmp/fullchain.pem /tmp/privkey.pem
```

Then restart the affected services:

```bash
docker exec ulaknode ulaknode-service restart postfix
docker exec ulaknode ulaknode-service restart dovecot
```

To verify the installed certificate at any time:

```bash
docker exec ulaknode ulaknode-cert show
docker exec ulaknode ulaknode-cert check
```

---

## 7. Add DKIM, SPF, and DMARC records

**DKIM** — generate a key for your domain and publish the resulting DNS record:

```bash
docker exec ulaknode ulaknode-dkim generate yourdomain.com
# prints the DNS TXT record to publish, then:
docker exec ulaknode ulaknode-service restart rspamd
```

To retrieve the record again later:

```bash
docker exec ulaknode ulaknode-dkim show yourdomain.com
```

**SPF** — generate the record value for your domain:

```bash
docker exec ulaknode ulaknode-spf generate yourdomain.com --mx
# prints the DNS TXT record to publish
```

**DMARC** — generate the record value. Start with `--policy none` to monitor before enforcing:

```bash
docker exec ulaknode ulaknode-dmarc generate yourdomain.com \
  --policy none \
  --rua mailto:postmaster@yourdomain.com
# prints the DNS TXT record to publish
```

All three commands only print the DNS records — publish them in your DNS provider's control panel.

---

## 8. Create domains, mailboxes, and aliases

**Domains** — add a domain before creating any mailboxes under it:

```bash
docker exec ulaknode ulaknode-domain add yourdomain.com
docker exec ulaknode ulaknode-domain list
```

**Mailboxes:**

```bash
# Add
docker exec ulaknode ulaknode-mailbox add user@yourdomain.com <password>

# Set a quota (optional)
docker exec ulaknode ulaknode-mailbox quota-set user@yourdomain.com 2G

# List all mailboxes for a domain
docker exec ulaknode ulaknode-mailbox list yourdomain.com

# Change password
docker exec ulaknode ulaknode-mailbox passwd user@yourdomain.com <newpassword>

# Remove
docker exec ulaknode ulaknode-mailbox remove user@yourdomain.com
```

**Aliases:**

```bash
# Add
docker exec ulaknode ulaknode-alias add info@yourdomain.com user@yourdomain.com

# List all aliases for a domain
docker exec ulaknode ulaknode-alias list yourdomain.com

# Remove
docker exec ulaknode ulaknode-alias remove info@yourdomain.com
```

---

## Verify everything is running

```bash
docker exec ulaknode ulaknode-service status postfix
docker exec ulaknode ulaknode-service status dovecot
docker exec ulaknode ulaknode-service status rspamd
docker exec ulaknode ulaknode-service status clamav
```

---

## Troubleshooting

- **Permission errors after editing configs:** run `docker exec ulaknode fix-permissions /etc/ulaknode`
- **Port 25 not reachable:** check your firewall rules and confirm your ISP/provider has unblocked the port
- **Service errors:** use `docker exec ulaknode ulaknode-errlog <service>` to inspect recent error logs
