# Stress Testing ulaknode

All tests assume a running container named `ulaknode-x2` with domain `aurio.no` and mailbox `tk@aurio.no`.

---

## 1. SMTP delivery volume (port 25, unauthenticated)

Uses `smtp-source` from the Postfix package. Sends messages directly to the MTA as if from an external server.

```bash
# 100 messages, 10 concurrent connections, 1KB body
docker exec ulaknode-x2 smtp-source -c -l 1024 -m 100 -s 10 \
  -f sender@aurio.no -t tk@aurio.no 127.0.0.1:25
```

Options:
- `-l` — message body size in bytes
- `-m` — total number of messages
- `-s` — number of concurrent SMTP sessions
- `-c` — display a counter

---

## 2. Authenticated submission (port 587)

Uses `swaks` from the client machine. Tests the full authenticated submission path including TLS and SASL.

```bash
for i in $(seq 1 50); do
  swaks --to tk@aurio.no --from tk@aurio.no \
    --server mail.aurio.no:587 --tls \
    --auth PLAIN --auth-user tk@aurio.no --auth-password PASSWORD \
    --body "stress test $i" --silent 1
done
```

---

## 3. Large message delivery

Tests the `message_size_limit` boundary. Default Postfix limit is 10MB.

```bash
# 5MB messages, 10 total, 2 concurrent sessions
docker exec ulaknode-x2 smtp-source -c -l 5120000 -m 10 -s 2 \
  -f sender@aurio.no -t tk@aurio.no 127.0.0.1:25
```

To raise the limit to 50MB (add to `postfix/conf/main.cf`):
```
message_size_limit = 52428800
```

---

## 4. IMAP concurrent connections

Uses `curl` (available inside the container) to simulate concurrent IMAP logins and INBOX fetches.

```bash
# Run 20 concurrent IMAP sessions, each listing the INBOX
for i in $(seq 1 20); do
  docker exec ulaknode-x2 curl -s \
    --url "imap://127.0.0.1/INBOX" \
    --user "tk@aurio.no:PASSWORD" \
    --ssl-reqd &
done
wait
```

---

## 5. Quota enforcement

Set a small quota, flood with messages, verify the 552 rejection.

```bash
# Set 1MB quota
docker exec ulaknode-x2 ulaknode-mailbox quota-set tk@aurio.no 1M

# Flood with 1KB messages until quota is exceeded
docker exec ulaknode-x2 smtp-source -c -l 1024 -m 2000 -s 5 \
  -f sender@aurio.no -t tk@aurio.no 127.0.0.1:25

# Check quota usage
docker exec ulaknode-x2 ulaknode-mailbox quota tk@aurio.no

# Reset quota when done
docker exec ulaknode-x2 ulaknode-mailbox quota-set tk@aurio.no 0
```

---

## Monitoring during tests

```bash
# Watch mail log in real time
docker exec ulaknode-x2 tail -f /var/log/mail.log

# Watch Dovecot log
docker exec ulaknode-x2 tail -f /var/log/dovecot.log

# Check mail queue depth
docker exec ulaknode-x2 mailq

# Count delivered messages in maildir
docker exec ulaknode-x2 find /var/mail/aurio.no/tk -type f | wc -l
```
