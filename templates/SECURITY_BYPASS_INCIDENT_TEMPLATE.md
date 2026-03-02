# Security Bypass Incident Template

Incident ID: {{INCIDENT_ID}}
Opened at (UTC): {{OPENED_AT}}
Owner: {{OWNER}}
Severity: {{SEVERITY}}

## 1) Trigger

- Why bypass was required: {{REASON}}
- Environment: {{ENVIRONMENT}}
- Affected release version: {{VERSION}}

## 2) Bypass Details

Select all used:

- [ ] ALLOW_INSECURE_BOOTSTRAP=1
- [ ] ALLOW_UNSIGNED=1
- [ ] ALLOW_UNVERIFIED=1
- [ ] NX_INSECURE_TLS=1
- [ ] RequireInstallerSignature disabled (PowerShell)
- [ ] Other: {{DETAILS}}

Start time (UTC): {{START_TIME}}
End time (UTC): {{END_TIME}}

## 3) Risk and Exposure

- Assets potentially exposed: {{ASSETS}}
- Threat model summary: {{THREAT_SUMMARY}}
- Detection coverage at time of bypass: {{COVERAGE}}

## 4) Containment and Recovery

- Immediate mitigations applied: {{MITIGATIONS}}
- Verification steps after recovery:
  - [ ] Re-enable strict signature checks
  - [ ] Re-run security regression checks
  - [ ] Re-sign and re-verify release assets
  - [ ] Validate runtime TLS settings

## 5) Root Cause

- Primary root cause: {{ROOT_CAUSE}}
- Contributing factors: {{FACTORS}}

## 6) Corrective Actions

- Action 1: {{ACTION}} (owner: {{OWNER}}, due: {{DATE}})
- Action 2: {{ACTION}} (owner: {{OWNER}}, due: {{DATE}})
- Action 3: {{ACTION}} (owner: {{OWNER}}, due: {{DATE}})

## 7) Closure

Closed at (UTC): {{CLOSED_AT}}
Security sign-off: {{NAME}}
Ops sign-off: {{NAME}}
