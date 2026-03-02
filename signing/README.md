# Release Signing

This directory contains the public key used to verify release checksum signatures.

- Public key: `release-signing.pub.pem`
- Signature file produced for each release: `SHA256SUMS.sig`
- Installer signatures: `install.sh.sig`, `install.ps1.sig`

## Sign a release

```bash
cd vms-server-releases
./scripts/generate-checksums.sh . --sign
```

By default, signing uses private key path:

- `/root/.vms-signing/release-signing-private.pem`

Override key path when needed:

```bash
VMS_SIGNING_KEY=/secure/path/private.pem ./scripts/generate-checksums.sh . --sign
```

## Verify before publishing

```bash
openssl dgst -sha256 -verify signing/release-signing.pub.pem \
  -signature SHA256SUMS.sig SHA256SUMS
openssl dgst -sha256 -verify signing/release-signing.pub.pem \
  -signature install.sh.sig install.sh
openssl dgst -sha256 -verify signing/release-signing.pub.pem \
  -signature install.ps1.sig install.ps1
sha256sum -c SHA256SUMS
```

## Key handling

- Never commit private keys to git.
- Keep private key in an HSM, vault, or offline encrypted storage.
- Restrict file permission to `600`.
- Rotate keys periodically and update installer pinned key hash when rotating.
