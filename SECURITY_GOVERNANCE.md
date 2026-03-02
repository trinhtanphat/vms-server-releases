# Security Governance

This document defines approval and control flow for release security.

## Ownership model

- Engineering owner: repository maintainer
- Security owner: reviewer for signing and trust chain controls
- Operations owner: reviewer for deployment safety and rollback

## Mandatory review scope

Changes touching these files require Security + Ops review:

- `install.sh`, `install.ps1`
- `scripts/generate-checksums.sh`
- `scripts/security-regression-check.sh`
- `scripts/security-regression-check.ps1`
- `signing/*`
- `.github/workflows/release-signing.yml`
- `.github/workflows/security-gate.yml`

## Required evidence before release

- Signature verification logs for:
  - `install.sh.sig`
  - `install.ps1.sig`
  - `SHA256SUMS.sig`
- Regression check output (`security-regression-check.sh`)
- Release docs generated from templates

## Bypass control policy

The following are emergency-only controls:

- `ALLOW_INSECURE_BOOTSTRAP`
- `ALLOW_UNSIGNED`
- `ALLOW_UNVERIFIED`
- `NX_INSECURE_TLS`
- `-RequireInstallerSignature:$false`

If any bypass is used:

1. Open incident ticket
2. Record reason and exposure
3. Define remediation deadline
4. Close incident only after strict mode is restored and validated
