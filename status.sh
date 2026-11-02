#!/system/bin/sh
# 查看 vivo-ai-call-bark 状态
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$BASE_DIR/config" ] && . "$BASE_DIR/config"
: "${WATCH_DIR:=$BASE_DIR}"

[ "$(id -u)" = "0" ] || { echo "please run as root: su -c 'sh $0'"; exit 1; }

PID="$WATCH_DIR/full.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "running (pid $(cat "$PID"))"
else
  echo "not running"
fi
[ -f "$WATCH_DIR/full_last_id" ] && echo "last_id=$(cat "$WATCH_DIR/full_last_id")"
[ -f "$WATCH_DIR/full.log" ] && { echo "--- last log ---"; tail -5 "$WATCH_DIR/full.log"; }
