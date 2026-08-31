#!/usr/bin/env bash
# Test the public OTLP ingestion endpoint with a valid OTLP/JSON log payload.
#
# Usage:
#   OTLP_HOST=https://otlp.voltrum.co OTLP_TOKEN=<clickstack-otlp-token> ./test-otlp.sh
set -euo pipefail

HOST="${OTLP_HOST:-https://otlp.voltrum.co}"
TOKEN="${OTLP_TOKEN:?set OTLP_TOKEN to the clickstack-otlp-token sops value}"
NOW_MS="$(date +%s)000"
NOW_NS="${NOW_MS}000000"
TRACE_ID="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
SPAN_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"

LOG_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$HOST/v1/logs" \
  -H 'content-type: application/json' \
  -H "authorization: $TOKEN" \
  -d @- <<EOF
{
  "resourceLogs": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "otlp-smoketest"}},
      {"key": "deployment.environment", "value": {"stringValue": "test"}}
    ]},
    "scopeLogs": [{
      "scope": {"name": "test-otlp.sh"},
      "logRecords": [{
        "timeUnixNano": "${NOW_NS}",
        "severityText": "INFO",
        "severityNumber": 9,
        "body": {"stringValue": "smoke test from test-otlp.sh"},
        "attributes": [{"key": "test.run", "value": {"stringValue": "$(date -u +%FT%TZ)"}}]
      }]
    }]
  }]
}
EOF
)"

TRACE_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$HOST/v1/traces" \
  -H 'content-type: application/json' \
  -H "authorization: $TOKEN" \
  -d @- <<EOF
{
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "otlp-smoketest"}},
      {"key": "deployment.environment", "value": {"stringValue": "test"}}
    ]},
    "scopeSpans": [{
      "scope": {"name": "test-otlp.sh"},
      "spans": [{
        "traceId": "${TRACE_ID}",
        "spanId": "${SPAN_ID}",
        "name": "otlp.smoketest",
        "kind": 1,
        "startTimeUnixNano": "${NOW_NS}",
        "endTimeUnixNano": "$((NOW_NS + 1000000))",
        "status": {"code": 1}
      }]
    }]
  }]
}
EOF
)"

printf 'logs: %s\ntraces: %s\n' "$LOG_CODE" "$TRACE_CODE"
if [[ "$LOG_CODE" != "200" || "$TRACE_CODE" != "200" ]]; then
  exit 1
fi

echo "→ check HyperDX Logs and Traces for service.name = otlp-smoketest"
