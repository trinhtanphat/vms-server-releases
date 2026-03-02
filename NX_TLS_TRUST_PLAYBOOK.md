# NX Upstream TLS Trust Playbook

This playbook explains how to keep `proxy_ssl_verify on` for NX upstream (`https://127.0.0.1:7001`) without using `NX_INSECURE_TLS=1`.

## Goal

- Keep TLS verification enabled in nginx.
- Trust NX certificate chain explicitly.
- Avoid insecure proxy mode in production.

## 1) Export NX certificate chain

On the NX host, export the server certificate (and intermediate CA if used).

Example (adjust path/source to your NX deployment):

```bash
openssl s_client -connect 127.0.0.1:7001 -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' > /tmp/nx-upstream-chain.pem
```

## 2) Install trusted chain for nginx

```bash
sudo mkdir -p /etc/nginx/trust
sudo cp /tmp/nx-upstream-chain.pem /etc/nginx/trust/nx-upstream-chain.pem
sudo chmod 644 /etc/nginx/trust/nx-upstream-chain.pem
```

## 3) Configure nginx upstream TLS verification

In generated nginx site config, for NX proxy locations (`/api`, `/rest`, `/hls`, `/media`):

```nginx
proxy_ssl_verify on;
proxy_ssl_trusted_certificate /etc/nginx/trust/nx-upstream-chain.pem;
proxy_ssl_server_name on;
```

If certificate CN/SAN does not match `127.0.0.1`, set expected name:

```nginx
proxy_ssl_name nx.your.internal.name;
```

## 4) Validate and reload

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 5) Runtime verification

```bash
curl -vk https://127.0.0.1:7001/api/ | head
curl -kI https://your-domain/rest/
```

Check nginx error logs for TLS verify failures:

```bash
sudo tail -f /var/log/nginx/error.log
```

## Emergency fallback

If production incident requires temporary bypass:

- Use installer/env override `NX_INSECURE_TLS=1`.
- Treat as temporary only.
- Create incident ticket and return to trusted chain mode ASAP.

## Acceptance criteria

- `proxy_ssl_verify on` active in all NX upstream locations.
- No TLS verification errors in nginx logs during normal traffic.
- `NX_INSECURE_TLS` not used in production environment variables.
