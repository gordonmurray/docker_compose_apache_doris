#!/usr/bin/env bash
# Shared by demo.sh and smoke-test.sh; not an entrypoint.
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_args=(--project-directory "$project_dir" -f "$project_dir/docker-compose.yml")
# Used by demo.sh after sourcing this file.
# shellcheck disable=SC2034
replicas=1
expected_nodes=1
case "${1:-}" in
  --cluster)
    compose_args+=(-f "$project_dir/docker-compose.cluster.yml" -p trying-doris-cluster)
    # shellcheck disable=SC2034
    replicas=3
    expected_nodes=3
    ;;
  "") ;;
  *) echo "Usage: $0 [--cluster]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Usage: $0 [--cluster]" >&2; exit 2; }

compose() { docker compose "${compose_args[@]}" "$@"; }
sql() {
  compose exec -T fe mysql --protocol=TCP -h127.0.0.1 -P9030 -uroot \
    --connect-timeout=5 --batch --raw --skip-column-names "$@"
}
produce() {
  compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server kafka:9092 --topic kafka_topic
}
diagnostics() {
  compose ps >&2 || true
  sql -e 'SHOW FRONTENDS; SHOW BACKENDS; USE products; SHOW ROUTINE LOAD;' >&2 || true
}
wait_for_count() {
  local query=$1 expected=$2 timeout=${3:-180} actual deadline=$((SECONDS + ${3:-180}))
  while (( SECONDS < deadline )); do
    if actual=$(sql -e "$query") && [[ "$actual" == "$expected" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out after ${timeout}s: expected $expected, last result: ${actual:-unavailable}" >&2
  diagnostics
  return 1
}
start_stack() {
  command -v docker >/dev/null || { echo "Install Docker with Compose v2 first." >&2; return 1; }
  compose up -d --wait --wait-timeout 300
  # Join is a quoted SQL identifier, not shell command substitution.
  # shellcheck disable=SC2016
  wait_for_count 'SELECT COUNT(*) FROM frontends() WHERE Alive = true AND `Join` = true' "$expected_nodes"
  wait_for_count 'SELECT COUNT(*) FROM backends() WHERE Alive = true' "$expected_nodes"
}
