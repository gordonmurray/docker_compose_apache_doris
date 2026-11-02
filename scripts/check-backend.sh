#!/usr/bin/env bash
set -euo pipefail

# An open HTTP port alone does not mean the backend has joined the cluster.
alive=$(mysql --protocol=TCP -hfe -P9030 -uroot --connect-timeout=5 -BN \
  -e "SELECT COUNT(*) FROM backends() WHERE Host = '${BE_ADDR%:*}' AND Alive = true")
[[ "$alive" == 1 ]]
