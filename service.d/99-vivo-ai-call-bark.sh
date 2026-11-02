#!/system/bin/sh
# Magisk / KernelSU service.d 自启脚本
# 安装：cp 99-vivo-ai-call-bark.sh /data/adb/service.d/ && chmod 755 /data/adb/service.d/99-vivo-ai-call-bark.sh
WATCH_DIR=/data/adb/ai-call-watch
[ -x "$WATCH_DIR/start.sh" ] || exit 0
/system/bin/sh "$WATCH_DIR/start.sh" >/dev/null 2>&1
