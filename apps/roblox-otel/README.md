# roblox-otel — Roblox → ClickStack ingestion

Luau SDK that ships logs from Roblox experiences into self-hosted ClickStack
(HyperDX) running on the QuadNix cluster.

- **Endpoints:** `https://otlp.voltrum.co/v1/logs` and `/v1/traces` (OTLP/HTTP JSON)
- **Auth:** `Authorization: <clickstack-otlp-token>` (RAW token — the
  standalone collector's bearertokenauth uses `scheme: ""`, no Bearer prefix)
  (the `clickstack-otlp-token` sops key == HyperDX `OTLP_AUTH_TOKEN`)
- **Search:** HyperDX UI at `https://hyperdx.voltrum.co`, filter
  `service.name: roblox`

## Layout

| File | Role |
|---|---|
| `src/OtelServer.luau` | Server module: independent log/span queues, batch (5s / 120 rec), OTLP JSON POST, backoff, `BindToClose` final flush. Creates the `OtelLogSink` RemoteEvent. |
| `src/OtelTrace.luau` | Pure span lifecycle, OTLP encoding, parent context, status, and log-correlation helpers. |
| `src/OtelClientBridge.client.luau` | LocalScript: forwards client `LogService.MessageOut` + `ScriptContext.ErrorDetailed` to the server RemoteEvent (throttled 20 msg / 5s). Clients can't call HttpService — relay only. |
| `src/ExampleUsage.server.luau` | Drop-in wiring example (boot/join/leave events). |
| `test-otlp.sh` | Smoke-test the public endpoint with curl. |
| `default.project.json` | Rojo project mapping. |

## Setup

1. **Rojo:** `rojo serve` with `default.project.json`, sync into a place.
2. **Studio:** enable *Game Settings → Security → Allow HTTP Requests*.
3. **Live servers:** enable HttpService for the experience in the Creator
   Dashboard (your experience → Settings → Security).
4. **Token:** set the server attribute before heavy logging:

   ```luau
   game:GetService("ServerScriptService"):SetAttribute("OtelToken", "<clickstack-otlp-token>")
   ```

   Get the token value: `sops --decrypt secrets/backbone-01.yaml | grep clickstack-otlp-token`
   (on the deploy machine). Never commit it.

5. Smoke-test without Roblox: `OTLP_TOKEN=... ./test-otlp.sh` → expect
   `logs: 200` and `traces: 200`, then search `otlp-smoketest` in HyperDX.

## API

```luau
local Otel = require(game.ServerScriptService.OtelServer)

Otel.info("Match started", { mode = "ranked", players = 8 })
Otel.warn("Odd state", { state = state })
Otel.error("Payment failed", { orderId = orderId })
Otel.log("FATAL", "unrecoverable", { phase = "boot" })

-- Real OTLP traces. Correlated logs use the span's IDs.
local span = Otel.startSpan("match.start", { mode = "ranked" }, nil, "SERVER")
Otel.info("Allocating match", { traceId = span.traceId, spanId = span.spanId })

local child = Otel.startSpan("match.allocate", nil, span:context())
child:finish("OK")
span:finish("OK") -- or span:fail("allocation timeout")

Otel.flushNow() -- flushes logs and completed spans; normally unnecessary
```

Record attributes captured automatically:
`roblox.place_id`, `roblox.universe_id`, `roblox.job_id`,
`roblox.server_type` (`live`/`studio`), `deployment.environment`,
`service.name=roblox`; client-relayed records add `roblox.player`,
`roblox.user_id`.

## Notes & limits

- Server-side only outbound HTTP; client logs ride the RemoteEvent relay.
- Queue is bounded (500). When full, least-severe buffered records are
  dropped first; incoming low-severity records are dropped when equal.
- Failed flushes requeue (backoff one cycle). `warn()`s from the module
  itself stay local-only by design (no loops).
- Studio "Test → Start" sessions need HttpService enabled or POSTs no-op.
- Spans are queued only when finished. Always call `span:finish("OK")` or
  `span:fail(message)`; unfinished spans are intentionally not exported.
- Span kinds: `INTERNAL` (default), `SERVER`, `CLIENT`, `PRODUCER`, `CONSUMER`.
- Pass `traceId` and `spanId` attributes from a span into log calls; the SDK
  promotes valid IDs to native OTLP fields so HyperDX links logs and traces.
