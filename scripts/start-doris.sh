#!/usr/bin/env bash
set -euo pipefail

role=${1:?Expected fe or be}
case "$role" in
  fe) entrypoint=/usr/local/bin/init_fe.sh ;;
  be) entrypoint=/usr/local/bin/entry_point.sh ;;
  *) echo "Expected fe or be" >&2; exit 2 ;;
esac

config="/opt/apache-doris/$role/conf/$role.conf"
# Keep the image's Java module options and other defaults. Replace only the
# settings in the mounted snippet; the image's entrypoint needs a writable file.
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z_0-9]*)= ]]; then
    key=${BASH_REMATCH[1]}
    sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" "$config"
    printf '\n%s\n' "$line" >> "$config"
  fi
done < "/demo/$role.conf"

[[ ${DORIS_JAVA_HEAP:?} =~ ^[1-9][0-9]*[mMgG]$ ]] || {
  echo "DORIS_JAVA_HEAP must be a size such as 512m or 2g" >&2
  exit 2
}
sed -i -E \
  "s/-Xmx[0-9]+[mMgG]/-Xmx${DORIS_JAVA_HEAP}/g; s/-Xms[0-9]+[mMgG]/-Xms256m/g" \
  "$config"
exec bash "$entrypoint"
