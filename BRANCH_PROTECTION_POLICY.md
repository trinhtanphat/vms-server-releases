# Branch Protection Policy (Recommended)

Apply this policy to the default branch (`main`) and any release branch.

## Required protections

- Require pull request before merging
- Require at least 2 approvals
- Require review from Code Owners
- Dismiss stale approvals when new commits are pushed
- Require conversation resolution before merge
- Require status checks to pass before merge:
  - `Security Gate / security-gate`
  - `Release Signing / sign-assets` (if used separately)
  - `Release Docs Skeleton / generate-release-docs` (optional if covered by Security Gate)
- Require branches to be up to date before merging
- Restrict force pushes and deletions
- Restrict who can push to protected branches

## Tag/release controls

- Only maintainers can create release tags (`v*`)
- All release tags must trigger `security-gate.yml`
- Release is valid only when:
  - signatures generated and attached
  - security regression checks pass
  - release docs artifact produced

## Emergency change protocol

For urgent fixes to installer/signing chain:

1. Open incident ticket first
2. Require Security + Ops approval
3. Merge via PR only (no direct push)
4. Re-run `security-gate.yml`
5. Attach post-incident report in release docs
