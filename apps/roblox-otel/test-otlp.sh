#!/usr/bin/env bash
# Test the public OTLP ingestion endpoint with a valid OTLP/JSON log payload.
#
# Usage:
#   OTLP_HOST=https://otlp.voltrum.co OTLP_TOKEN=<clickstack-otlp-token> ./test-otlp.sh
set -euo pipefail

HOST="${OTLP_HOST:-https://otlp.voltrum.co}"
TOKEN="${OTLP_TOKEN:?set OTLP_TOKEN to the clickstack-otlp-token sops value}"
NOW_MS="$(date +%s)000"

curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$HOST/v1/logs" \
  -H 'content-type: application/json' \
  -H "authorization: Bearer $TOKEN" \
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
        "timeUnixNano": "${NOW_MS}000000",
        "severityText": "INFO",
        "severityNumber": 9,
        "body": {"stringValue": "smoke test from test-otlp.sh"},
        "attributes": [{"key": "test.run", "value": {"stringValue": "$(date -u +%FT%TZ)"}}]
      }]
    }]
  }]
}
EOF

echo "→ check it in HyperDX: search service.name = otlp-smoketest"
