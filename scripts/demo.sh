#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

start_stack
compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 --create --if-not-exists \
  --topic kafka_topic --partitions 1 --replication-factor 1

sed "s/\${REPLICATION_NUM}/$replicas/g" "$project_dir/sql/schema.sql" | sql
# SHOW ROUTINE LOAD omits stopped jobs. Reuse an active job on repeated runs.
jobs=$(sql --database=products --column-names -e 'SHOW ROUTINE LOAD;')
state=$(awk -F '\t' 'NR == 1 {for (i = 1; i <= NF; i++) col[$i] = i; next}
  col["Name"] && col["State"] && $(col["Name"]) == "kafka_fruit" {print $(col["State"])}' <<< "$jobs")
case "$state" in
  "") sql < "$project_dir/sql/routine-load.sql" ;;
  RUNNING|NEED_SCHEDULE) ;;
  *)
    echo "Routine Load is $state. Inspect SHOW ROUTINE LOAD FOR products.kafka_fruit before resuming or resetting." >&2
    diagnostics
    exit 1
    ;;
esac

printf 'oranges,0.45\napples,0.60\nbananas,0.30\n' | produce
wait_for_count "SELECT COUNT(*) FROM products.kafka_table WHERE (fruit = 'oranges' AND price = 0.45) OR (fruit = 'apples' AND price = 0.60) OR (fruit = 'bananas' AND price = 0.30)" 3
sql -e "SELECT fruit, price FROM products.kafka_table WHERE fruit IN ('oranges', 'apples', 'bananas') ORDER BY fruit;"
