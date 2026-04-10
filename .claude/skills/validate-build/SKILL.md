---
name: validate-build
description: Run the full validation pipeline — unit tests (offline) and optionally E2E tests (requires TradingView). Use before committing or after a refactor.
---

# Validate Build

Run all quality checks before committing.

## Step 1: Unit Tests (always run)

```bash
npm run test:unit
```

This runs `pine_analyze.test.js` and `cli.test.js` — offline tests that don't need TradingView. Takes ~2 seconds.

**Must pass before committing.**

## Step 2: E2E Tests (conditional)

Check if TradingView is running:
```bash
curl -s http://localhost:9222/json/version > /dev/null 2>&1 && echo "TradingView is running" || echo "TradingView is NOT running"
```

If running, offer to run E2E tests:
```bash
npm run test:e2e
```

These test all 70+ MCP tools against a live TradingView instance. They take ~30 seconds.

If TradingView is not running, skip E2E and note it in the report.

## Step 3: Report

```
Validation Results:
- Unit tests: PASS/FAIL (X/Y tests)
- E2E tests: PASS/FAIL/SKIPPED (TradingView not running)
- Overall: READY TO COMMIT / FIX ISSUES FIRST
```
