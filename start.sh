#!/system/bin/sh
# 启动 vivo-ai-call-bark（需要 root）
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$BASE_DIR/config" ] && . "$BASE_DIR/config"
: "${WATCH_DIR:=$BASE_DIR}"

[ "$(id -u)" = "0" ] || { echo "please run as root: su -c 'sh $0'"; exit 1; }

PID="$WATCH_DIR/full.pid"
if [ -f "$PID" ]; then
  old=$(cat "$PID" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    echo "already running (pid $old)"
    exit 0
  fi
fi

mkdir -p "$WATCH_DIR" 2>/dev/null

if command -v setsid >/dev/null 2>&1; then
  if command -v nohup >/dev/null 2>&1; then
    setsid nohup /system/bin/sh "$BASE_DIR/full_push.sh" >> "$WATCH_DIR/full.log" 2>&1 < /dev/null &
  else
    setsid /system/bin/sh "$BASE_DIR/full_push.sh" >> "$WATCH_DIR/full.log" 2>&1 < /dev/null &
  fi
else
  nohup /system/bin/sh "$BASE_DIR/full_push.sh" >> "$WATCH_DIR/full.log" 2>&1 < /dev/null &
fi

sleep 1
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "started (pid $(cat "$PID"))"
else
  echo "failed to start; check $WATCH_DIR/full.log"
  exit 1
fi
