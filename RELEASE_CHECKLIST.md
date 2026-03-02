# Release Checklist

Use this checklist for each release tag.

## 1) Pre-release

- [ ] All critical/high security issues triaged
- [ ] `install.sh` and `install.ps1` updated with final changes
- [ ] `CODEOWNERS` includes Security/Ops reviewers for installer/signing paths
- [ ] Branch protection policy requirements are enabled on `main`
- [ ] Initialize release governance docs:

```bash
./scripts/init-release-docs.sh <version> release-docs
```
- [ ] Regression checks pass locally:

```bash
cd vms-server-releases
./scripts/security-regression-check.sh .
```

## 2) Sign artifacts

- [ ] Private signing key available in secure environment
- [ ] Generate checksums + signatures:

```bash
cd vms-server-releases
./scripts/generate-checksums.sh . --sign
```

- [ ] Verify signatures:

```bash
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.sh.sig install.sh
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature install.ps1.sig install.ps1
openssl dgst -sha256 -verify signing/release-signing.pub.pem -signature SHA256SUMS.sig SHA256SUMS
sha256sum -c SHA256SUMS
```

## 3) Publish release

- [ ] Tag and push release
- [ ] Attach all required assets:
  - [ ] `install.sh`
  - [ ] `install.sh.sig`
  - [ ] `install.ps1`
  - [ ] `install.ps1.sig`
  - [ ] `SHA256SUMS`
  - [ ] `SHA256SUMS.sig`
  - [ ] binaries (`vms-server-*.tar.gz/.zip`, plugins packages)
- [ ] Confirm CI workflow `.github/workflows/release-signing.yml` succeeded
- [ ] Confirm CI workflow `.github/workflows/release-docs.yml` produced artifact `release-docs-<version>`
- [ ] Confirm CI workflow `.github/workflows/security-gate.yml` succeeded and artifact `security-gate-<version>` is available

## 4) Post-release validation

- [ ] Linux bootstrap verification works:

```bash
./scripts/bootstrap-install.sh latest
```

- [ ] Windows bootstrap verification works:

```powershell
.\scripts\bootstrap-install.ps1 -Version latest
```

- [ ] Installers reject insecure stdin/pipe by default
- [ ] Release notes include security changes and emergency override flags

## 5) Emergency controls review

- [ ] Emergency bypass flags documented and approved:
  - `ALLOW_INSECURE_BOOTSTRAP=1`
  - `ALLOW_UNSIGNED=1`
  - `ALLOW_UNVERIFIED=1`
  - `NX_INSECURE_TLS=1`
- [ ] Incident ticket required if any bypass is used in production
- [ ] If bypass used, fill incident report from:
  - `templates/SECURITY_BYPASS_INCIDENT_TEMPLATE.md`
