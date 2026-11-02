#!/system/bin/sh
# 安装 vivo-ai-call-bark（需要 root）
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = "0" ] || { echo "please run as root: su -c 'sh $0'"; exit 1; }

DEST=${WATCH_DIR:-/data/adb/ai-call-watch}
mkdir -p "$DEST" || { echo "cannot create $DEST"; exit 1; }

for f in full_push.sh start.sh stop.sh status.sh; do
  cp -f "$BASE_DIR/$f" "$DEST/$f" || exit 1
  chmod 755 "$DEST/$f"
done

mkdir -p "$DEST/service.d"
cp -f "$BASE_DIR/service.d/99-vivo-ai-call-bark.sh" "$DEST/service.d/" || exit 1
chmod 755 "$DEST/service.d/99-vivo-ai-call-bark.sh"

if [ ! -f "$DEST/config" ]; then
  cp -f "$BASE_DIR/config.example" "$DEST/config"
  echo "created $DEST/config"
fi

echo "installed to $DEST"
echo "next: edit $DEST/config (set BARK_URL), then:"
echo "  su -c 'sh $DEST/start.sh'"
