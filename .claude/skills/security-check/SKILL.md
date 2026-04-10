---
name: security-check
description: Scan staged files for API keys, secrets, and hardcoded credentials before committing. MANDATORY before any commit that touches trading code, .env handling, or API integrations.
---

# Security Check — Pre-Commit Audit

This project handles **real money** via BitGet API. A leaked key means unauthorized trades on a live exchange. Run this check before every commit.

## Step 1: Check Staged Files

```bash
git diff --cached --name-only
```

If no files are staged, remind the user to stage first.

## Step 2: Scan for Secrets

Run against all staged content:

```bash
git diff --cached
```

Search the diff output for these patterns (case-insensitive):

### High-Severity (block commit)
- `BITGET_API_KEY`, `BITGET_SECRET_KEY`, `BITGET_PASSPHRASE`
- `API_KEY=`, `SECRET_KEY=`, `PASSPHRASE=`
- `Bearer ` followed by a token string
- `-----BEGIN.*PRIVATE KEY-----`
- Base64 strings longer than 40 characters that look like API secrets
- Any `.env` file being staged

### Medium-Severity (warn)
- `api.bitget.com` with inline credentials
- Hardcoded URLs with auth tokens in query params
- `password`, `secret`, `token` assigned to string literals (not variable names)
- `hmac`, `sha256` with inline key material

## Step 3: Check .env Protection

Verify `.env` is in `.gitignore`:
```bash
grep -q "^\.env$" .gitignore && echo "OK: .env is gitignored" || echo "DANGER: .env is NOT in .gitignore"
```

Verify no `.env` files are staged:
```bash
git diff --cached --name-only | grep -i "\.env"
```

## Step 4: Check safety-check-log.json

This file contains real BitGet order IDs. It should NOT be committed:
```bash
git diff --cached --name-only | grep "safety-check-log.json"
```

## Step 5: Report

### If clean:
```
Security Check: PASS
No secrets or sensitive data found in staged changes.
Safe to commit.
```

### If issues found:
```
Security Check: BLOCKED
[list each finding with file:line and the pattern matched]
Action: Remove sensitive data before committing.
```

NEVER proceed with a commit if high-severity issues are found.
