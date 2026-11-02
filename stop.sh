#!/system/bin/sh
# 停止 vivo-ai-call-bark
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$BASE_DIR/config" ] && . "$BASE_DIR/config"
: "${WATCH_DIR:=$BASE_DIR}"

[ "$(id -u)" = "0" ] || { echo "please run as root: su -c 'sh $0'"; exit 1; }

PID="$WATCH_DIR/full.pid"
if [ ! -f "$PID" ]; then
  echo "not running"
  exit 0
fi

pid=$(cat "$PID" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
  fi
  echo "stopped (pid $pid)"
else
  echo "not running"
fi
rm -f "$PID"
