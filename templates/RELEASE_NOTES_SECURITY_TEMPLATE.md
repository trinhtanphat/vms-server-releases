# Security Release Notes Template

Release version: {{VERSION}}
Release date: {{DATE_UTC}}
Prepared by: {{OWNER}}

## 1) Scope

- Repositories in scope:
  - vms-server-releases
  - vms-server
  - vms-client-web
  - vms-client-desktop
  - vms-license-server
  - nxmeta-analytics-plugins
- Environments impacted: {{ENVIRONMENTS}}

## 2) Security Changes Included

### Installer trust chain

- [ ] install.sh signature verification enforced
- [ ] install.ps1 signature verification enforced
- [ ] SHA256SUMS signature verification enforced
- [ ] Public key hash pin validated

### Runtime hardening

- [ ] Linux service non-root execution verified
- [ ] TLS verification defaults verified
- [ ] NX upstream trust chain configured (if used)
- [ ] Emergency bypass flags disabled in production

### Supply chain

- [ ] Release signatures generated in trusted environment
- [ ] CI release-signing workflow successful
- [ ] Security regression checks passed

## 3) Verification Evidence

- Workflow run URL: {{CI_RUN_URL}}
- Signature verification logs:
  - install.sh.sig: {{LOG_OR_ARTIFACT}}
  - install.ps1.sig: {{LOG_OR_ARTIFACT}}
  - SHA256SUMS.sig: {{LOG_OR_ARTIFACT}}
- Regression check output: {{LOG_OR_ARTIFACT}}

## 4) Risk Assessment

- Residual critical risks: {{NONE_OR_LIST}}
- Residual medium risks: {{NONE_OR_LIST}}
- Accepted risks (with approver): {{LIST}}

## 5) Break-glass Usage

- Any bypass used during release? {{YES_NO}}
- If yes, incident ticket: {{INCIDENT_ID}}
- Expiration/remediation deadline: {{DEADLINE}}

## 6) Approval

- Security approver: {{NAME}}
- Engineering approver: {{NAME}}
- Operations approver: {{NAME}}
- Final go-live decision: {{GO_NO_GO}}
