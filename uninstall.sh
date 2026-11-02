#!/system/bin/sh
# 卸载 vivo-ai-call-bark（需要 root）。会删除配置、日志和状态。
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$BASE_DIR/config" ] && . "$BASE_DIR/config"
: "${WATCH_DIR:=$BASE_DIR}"

[ "$(id -u)" = "0" ] || { echo "please run as root: su -c 'sh $0'"; exit 1; }

[ -x "$BASE_DIR/stop.sh" ] && sh "$BASE_DIR/stop.sh" >/dev/null 2>&1
rm -rf "$WATCH_DIR"
echo "removed $WATCH_DIR"
