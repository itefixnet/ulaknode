# Brute-force protection with Fail2ban

ulaknode does not run Fail2ban inside the container. Fail2ban works by writing `iptables` rules, and in a Docker container with bridge networking those rules apply only to the container's network namespace — traffic from the outside still arrives unrestricted. Running Fail2ban on the **host** blocks attacking IPs at the right place: before traffic reaches the container at all.

```
attacker → host iptables (Fail2ban blocks here) → Docker bridge → ulaknode
```

What's already protecting you inside the container:

- **Rspamd greylisting** — delays unknown senders, eliminates most bot-originated spam
- **Rspamd RBL/SURBL checks** — rejects mail from known bad IPs and domains
- **Dovecot `auth_failure_delay`** — slows down IMAP password guessing

Fail2ban on the host adds network-level blocking for sustained brute-force attacks on SMTP and IMAP ports.

---

## Requirements

- Host OS: Debian / Ubuntu (or any Linux with `iptables` or `nftables`)
- ulaknode logs mounted to a host directory (recommended: `/srv/mail/logs`)
- Fail2ban 0.11+

---

## 1. Mount logs to a host directory

In your `docker run` command or compose file, mount the log volume to a fixed host path:

```bash
docker run -d \
  -v /srv/mail/logs:/var/log \
  ... \
  ulaknode:latest
```

Or in `docker-compose.yml`:

```yaml
volumes:
  - /srv/mail/logs:/var/log
```

After this, ulaknode's mail log is at `/srv/mail/logs/mail.log` on the host.

---

## 2. Install Fail2ban

```bash
apt install fail2ban
```

---

## 3. Create filters

**`/etc/fail2ban/filter.d/ulaknode-smtp.conf`** — SMTP authentication failures:

```ini
[Definition]
failregex = warning: [\w./]+\[<HOST>\]: SASL .* authentication failed
            NOQUEUE: reject: RCPT from \[<HOST>\]:.* 550
ignoreregex =
```

**`/etc/fail2ban/filter.d/ulaknode-imap.conf`** — IMAP/Dovecot authentication failures:

```ini
[Definition]
failregex = auth failed, \d+ attempts in \d+ secs: user=<\S+>, method=\S+, rip=<HOST>
            Aborted login \(auth failed.*\): user=<\S+>, method=\S+, rip=<HOST>
ignoreregex =
```

---

## 4. Create jails

**`/etc/fail2ban/jail.d/ulaknode.conf`**:

```ini
[ulaknode-smtp]
enabled  = true
port     = smtp,submission
filter   = ulaknode-smtp
logpath  = /srv/mail/logs/mail.log
maxretry = 5
findtime = 10m
bantime  = 1h
action   = iptables-multiport[name=ulaknode-smtp, port="25,587"]

[ulaknode-imap]
enabled  = true
port     = imap,imaps
filter   = ulaknode-imap
logpath  = /srv/mail/logs/dovecot.log
maxretry = 5
findtime = 10m
bantime  = 1h
action   = iptables-multiport[name=ulaknode-imap, port="143,993"]
```

Adjust `bantime` and `maxretry` to taste. A `bantime` of `24h` or `-1` (permanent) is reasonable for mail servers.

---

## 5. Enable and start

```bash
systemctl enable fail2ban
systemctl restart fail2ban

# Verify jails are active
fail2ban-client status
fail2ban-client status ulaknode-smtp
fail2ban-client status ulaknode-imap
```

---

## 6. Test

Trigger a few deliberate authentication failures from a test IP, then confirm it gets banned:

```bash
fail2ban-client status ulaknode-smtp
# → "Banned IP list: <test-ip>"
```

To unban manually:

```bash
fail2ban-client set ulaknode-smtp unbanip <ip>
```

---

## Persistent bans across reboots

By default, bans are lost on Fail2ban restart. To persist them:

```ini
# /etc/fail2ban/jail.d/ulaknode.conf — add to each jail:
bantime.increment = true
bantime.multiplier = 24
bantime.maxtime = 30d
```

This progressively extends ban times for repeat offenders up to 30 days.

---

## If your host uses nftables

Replace the `action` lines with:

```ini
action = nftables-multiport[name=ulaknode-smtp, port="25,587", protocol=tcp]
```

Check which backend your system uses:

```bash
fail2ban-client get dbfile   # shows backend in use
nft list ruleset 2>/dev/null | head -5
```
