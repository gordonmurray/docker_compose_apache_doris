#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"$project_dir/scripts/demo.sh" "$@"
# A unique message proves live Kafka ingestion even when old demo rows exist.
probe="smoke_${SECONDS}_$(date +%s)_${RANDOM}"
cleanup() { sql -e "DELETE FROM products.kafka_table WHERE fruit = '$probe';" >/dev/null || true; }
trap cleanup EXIT
printf '%s,9.99\n' "$probe" | produce
wait_for_count "SELECT COUNT(*) FROM products.kafka_table WHERE fruit = '$probe' AND price = 9.99" 1
echo "PASS: $expected_nodes frontend(s), $expected_nodes backend(s), and a fresh Kafka message queried in Doris."
