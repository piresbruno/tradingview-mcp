# Architecture

## Overview

tradingview-mcp is a bridge between AI agents and TradingView Desktop. It exposes 78 MCP tools that read and control a live chart via Chrome DevTools Protocol (CDP).

```
                  ┌─────────────┐     ┌──────────────┐
                  │ Claude Code │     │  Terminal CLI │
                  │  (MCP stdio)│     │   (tv ...)    │
                  └──────┬──────┘     └──────┬────────┘
                         │                   │
              ┌──────────▼──────────┐ ┌──────▼──────────┐
              │   src/tools/*.js    │ │ src/cli/commands/ │
              │  (MCP tool defs)   │ │ (CLI command defs)│
              └──────────┬──────────┘ └──────┬──────────┘
                         │                   │
                         └────────┬──────────┘
                                  │
                       ┌──────────▼──────────┐
                       │   src/core/*.js     │
                       │  (business logic)   │
                       │  17 modules, 3300 LOC│
                       └──────────┬──────────┘
                                  │
                       ┌──────────▼──────────┐
                       │  src/connection.js  │
                       │  (CDP client)       │
                       │  localhost:9222     │
                       └──────────┬──────────┘
                                  │
                       ┌──────────▼──────────┐
                       │  TradingView Desktop│
                       │  (Electron/Chromium)│
                       └─────────────────────┘

         ┌───────────────────┐
         │  scalper-run.js   │  ← Standalone, NOT part of the MCP server
         │  (BitGet REST API)│     Uses api.bitget.com directly
         └───────────────────┘
```

## Layer Responsibilities

### Entry Layer — Two interfaces, same core

| Interface | Entry Point | Purpose |
|-----------|-------------|---------|
| MCP Server | `src/server.js` | stdio transport for Claude Code; registers 78 tools with Zod schemas |
| CLI | `src/cli/index.js` | Terminal commands (`tv quote`, `tv ohlcv`, etc.); JSON output |

Both call the same core functions — neither contains business logic.

### Tool Wrappers — `src/tools/*.js`

Each file exports a `register*Tools(server)` function that defines MCP tools using the SDK:

```
server.tool(name, description, zodSchema, handler)
  → handler calls core.module.function()
  → wraps result with jsonResult() from _format.js
```

`_format.js` converts any object into MCP-compliant format:
```js
{ content: [{ type: 'text', text: JSON.stringify(obj) }], isError?: true }
```

15 tool files register tools across domains: chart, data, pine, replay, drawing, alerts, batch, capture, watchlist, indicators, ui, pane, tab, health, morning.

### CLI Commands — `src/cli/commands/*.js`

Each file calls `register(name, config)` from `src/cli/router.js`:

```
register('ohlcv', {
  options: { count: { type: 'string', short: 'n' }, ... },
  handler: (opts) => core.data.getOhlcv({ count: Number(opts.count) })
})
```

The router uses Node.js built-in `parseArgs` — zero dependencies. Exit codes: 0 (success), 1 (error), 2 (CDP connection failure).

### Core Logic — `src/core/*.js`

The business logic layer. 17 modules, ~3300 lines total. Each module exports async functions that evaluate JavaScript in the TradingView browser context via CDP.

| Module | LOC | Key Functions |
|--------|-----|---------------|
| `pine.js` | 619 | `compile()`, `setSource()`, `getSource()`, `getErrors()`, `analyze()` |
| `data.js` | 454 | `getOhlcv()`, `getPineLines()`, `getPineLabels()`, `getPineTables()`, `getStudyValues()` |
| `stream.js` | 335 | `streamQuote()`, `streamBars()`, `streamAll()` |
| `ui.js` | 293 | `openPanel()`, `click()`, `fullscreen()`, `switchLayout()` |
| `health.js` | 251 | `healthCheck()`, `discover()`, `launch()` |
| `chart.js` | 225 | `getState()`, `setSymbol()`, `setTimeframe()`, `manageIndicator()` |
| `morning.js` | 164 | `brief()`, `sessionSave()`, `sessionGet()` |
| `pane.js` | 157 | `create()`, `remove()`, `list()`, `moveTo()` |
| `watchlist.js` | 132 | `get()`, `add()`, `remove()`, `setActive()` |
| `alerts.js` | 123 | `create()`, `list()`, `delete()` |
| `replay.js` | 113 | `start()`, `stop()`, `step()`, `trade()`, `status()` |
| `tab.js` | 106 | `list()`, `select()`, `create()`, `close()` |
| `batch.js` | — | `run()` — multi-symbol operations |
| `drawing.js` | — | `shape()`, `list()`, `removeOne()`, `clear()` |
| `capture.js` | — | `screenshot()` — saves to `screenshots/` |

### CDP Connection — `src/connection.js`

Single persistent CDP client with automatic reconnection.

**Key exports:**
- `getClient()` — returns cached client or reconnects (liveness check via `Runtime.evaluate('1')`)
- `evaluate(expression, opts)` — executes JS in the browser context
- `evaluateAsync(expression)` — evaluate with `awaitPromise: true`
- `KNOWN_PATHS` — pre-verified paths into TradingView's internal API

**Target discovery:** Fetches `/json/list` from CDP port, prefers URLs containing `tradingview.com/chart`.

**Reconnection:** Exponential backoff (500ms base, max 30s, 5 retries).

## Pine Graphics Extraction

Custom Pine indicators draw visual elements (lines, labels, tables, boxes) that are invisible to standard data tools. The extraction path navigates TradingView's internal object model:

```
TradingView Internal Object Path:
─────────────────────────────────
dataSources()                          ← All indicators on chart
  └─ source._graphics                 ← Graphics container per indicator
      └─ _primitivesCollection
          ├─ dwglines.get('trend')     ← Lines (horizontal levels, trend lines)
          ├─ dwglabels.get('text')     ← Labels (price annotations)
          ├─ dwgtablecells             ← Tables (session stats, dashboards)
          │   └─ .get('tableCells')
          └─ dwgboxes.get('bbox')      ← Boxes (price zones)
              └─ .get(false)
                  └─ _primitivesDataById  ← Map<id, primitive_data>
```

`data.js` builds JavaScript strings via `buildGraphicsJS(collectionName, mapKey, filter)`, evaluates them in the browser, and processes the raw primitives into structured JSON. The `study_filter` parameter targets a specific indicator by name substring.

## Scalper Bot — `scalper-run.js`

**Completely separate** from the MCP server. Does not use `src/core/`, `src/tools/`, or CDP.

- Connects directly to BitGet REST API (`api.bitget.com`)
- Authenticates with HMAC-SHA256 signatures using keys from `.env`
- Implements a 10-second momentum strategy: VWAP + EMA(8) + RSI(3) on XRP/USDT
- Strategy config lives in `rules.json`
- Audit trail written to `safety-check-log.json`
- Anti-wash-trading lock handling with retry logic

## File Naming Conventions

| Prefix | Domain |
|--------|--------|
| `chart_*` | Chart control (symbol, timeframe, type) |
| `data_*` | Data extraction (OHLCV, indicators, Pine graphics) |
| `pine_*` | Pine Script (edit, compile, analyze) |
| `draw_*` | Drawing tools (shapes, lines) |
| `replay_*` | Backtest replay |
| `alert_*` | Alert management |
| `batch_*` | Multi-symbol operations |
| `ui_*` | UI automation |
| `pane_*` / `tab_*` | Layout management |
| `watchlist_*` | Watchlist operations |
| `indicator_*` | Indicator settings |
| `capture_*` | Screenshots |
| `morning_*` / `session_*` | Morning brief workflow |
| `tv_*` / `quote_*` | Misc (launch, health, quotes) |
