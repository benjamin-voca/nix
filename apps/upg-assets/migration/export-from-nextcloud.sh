#!/usr/bin/env bash
# Export authoring data from the Nextcloud pod for migration.
# Does NOT delete anything in Nextcloud.
set -euo pipefail

OUT="${1:-/tmp/upg-nextcloud-export}"
POD="${POD:-$(kubectl -n nextcloud get pod -l app.kubernetes.io/name=nextcloud -o jsonpath='{.items[0].metadata.name}')}"

mkdir -p "$OUT"
echo "Exporting from pod $POD -> $OUT"

kubectl -n nextcloud exec "$POD" -- \
  tar -C /var/www/html/data/admin/files -cf - UltimateBladeGrounds \
  | tar -C "$OUT" -xf -

mkdir -p "$OUT/Klajdi-files"
kubectl -n nextcloud exec "$POD" -- \
  tar -C /var/www/html/data/Klajdi/files -cf - \
    second-m1.blend third-m1.blend fourth-m1.blend \
    second-m1.rbxanim third-m1.rbxanim fourth-m1.rbxanim \
  2>/dev/null | tar -C "$OUT/Klajdi-files" -xf - || true

echo "Export complete:"
du -sh "$OUT/UltimateBladeGrounds" "$OUT/Klajdi-files" 2>/dev/null || true
find "$OUT" -type f ! -name '.DS_Store' | wc -l
