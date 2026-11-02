#!/system/bin/sh
# vivo-ai-call-bark
# 把 vivo 小V电话助手（AI 通话代接）挂机后的完整对话推送到 Bark。
# 必须以 root 运行。

BASE_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -f "$BASE_DIR/config" ] && . "$BASE_DIR/config"

: "${WATCH_DIR:=$BASE_DIR}"
: "${SMARTANSWER_DB:=/data/data/com.vivo.smartanswer/databases/smartdatabase.db}"
: "${SMS_FORWARDER_DB:=/data/data/cn.ppps.forwarder/databases/sms_forwarder.db}"
: "${POLL_SECONDS:=5}"
: "${MARKER_STABLE_SECONDS:=5}"
: "${FALLBACK_STABLE_SECONDS:=12}"
: "${ENDTIME_TOLERANCE_MS:=4000}"
: "${LOG_MAX_BYTES:=1048576}"

LOG="$WATCH_DIR/full.log"
ID_FILE="$WATCH_DIR/full_last_id"
PID_FILE="$WATCH_DIR/full.pid"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
die() { log "ERROR: $*"; echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "must run as root (use: su -c 'sh $0')"

mkdir -p "$WATCH_DIR" 2>/dev/null
[ -d "$WATCH_DIR" ] || die "cannot create $WATCH_DIR"

# 单实例
if [ -f "$PID_FILE" ]; then
  old=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT INT TERM

# sqlite3
if [ -z "${SQLITE3:-}" ]; then
  for c in sqlite3 /system/bin/sqlite3 /data/data/com.termux/files/usr/bin/sqlite3; do
    if command -v "$c" >/dev/null 2>&1; then
      SQLITE3=$c
      break
    fi
  done
fi
[ -n "${SQLITE3:-}" ] || die "sqlite3 not found (install Termux or a busybox with sqlite3)"
command -v "$SQLITE3" >/dev/null 2>&1 || die "sqlite3 not executable: $SQLITE3"

# curl
if [ -z "${CURL:-}" ]; then
  for c in curl /system/bin/curl /data/data/com.termux/files/usr/bin/curl; do
    if command -v "$c" >/dev/null 2>&1; then
      CURL=$c
      break
    fi
  done
fi
[ -n "${CURL:-}" ] || die "curl not found (install Termux or a busybox with curl)"

# 数据库检查
[ -r "$SMARTANSWER_DB" ] || die "cannot read $SMARTANSWER_DB (root required, or 小V电话助手 not installed)"
"$SQLITE3" -readonly "$SMARTANSWER_DB" "select chat_json from smart_answer limit 1;" >/dev/null 2>&1 \
  || die "schema mismatch: smart_answer/chat_json not found"
"$SQLITE3" -readonly "$SMARTANSWER_DB" "select json_valid('[]');" 2>/dev/null | grep -q 1 \
  || die "sqlite3 lacks JSON1 support"

# Bark 地址：优先 config 里的 BARK_URL，否则读 SmsForwarder 的 Bark 通道
if [ -z "${BARK_URL:-}" ]; then
  [ -r "$SMS_FORWARDER_DB" ] || die "BARK_URL is empty and SmsForwarder DB not found; set BARK_URL in config"
  BARK_URL=$("$SQLITE3" -readonly "$SMS_FORWARDER_DB" "select json_extract(json_setting,'\$.server') from Sender where type=2 and status=1 order by id limit 1;" 2>/dev/null)
fi
[ -n "${BARK_URL:-}" ] || die "BARK_URL is empty; set it in config"
case "$BARK_URL" in
  */) ;;
  *) BARK_URL="$BARK_URL/" ;;
esac

# 首次启动：从当前最后一条之后开始，避免补推历史
if [ ! -f "$ID_FILE" ]; then
  "$SQLITE3" -readonly "$SMARTANSWER_DB" "select ifnull(max(_id),0) from smart_answer;" > "$ID_FILE"
fi
last_id=$(cat "$ID_FILE" 2>/dev/null)
[ -z "$last_id" ] && last_id=0

log "start last_id=$last_id pid=$$"

while true; do
  ids=$("$SQLITE3" -readonly "$SMARTANSWER_DB" "select _id from smart_answer where _id > $last_id order by _id;" 2>/dev/null)

  for rid in $ids; do
    prev=-1
    stable=0
    marker_stable=0
    waited=0
    len=0
    dur=0
    reason=""

    # 完成判定：
    # 1) 最后一条 state=3（对方中途挂断，最后一句被标记结束）
    # 2) 最后一条 endTime 接近 during_time（正常说完后挂断）
    # 满足后连续 MARKER_STABLE_SECONDS 秒不再变化就推；
    # 异常情况下回退到 FALLBACK_STABLE_SECONDS 秒长度稳定。
    while true; do
      len=$("$SQLITE3" -readonly "$SMARTANSWER_DB" "select ifnull(length(chat_json),0) from smart_answer where _id=$rid;" 2>/dev/null)
      dur=$("$SQLITE3" -readonly "$SMARTANSWER_DB" "select ifnull(during_time,0) from smart_answer where _id=$rid;" 2>/dev/null)
      [ -z "$len" ] && len=0
      [ -z "$dur" ] && dur=0

      if [ "$len" -gt 0 ] && [ "$dur" -gt 0 ]; then
        if [ "$len" = "$prev" ]; then
          stable=$((stable + 1))
        else
          stable=0
        fi
      else
        stable=0
      fi
      prev=$len

      last=$("$SQLITE3" -readonly "$SMARTANSWER_DB" "select ifnull(json_extract(j.value,'\$.state'),'') || ',' || ifnull(json_extract(j.value,'\$.endTime'),'') from smart_answer s, json_each(s.chat_json) j where s._id=$rid and json_extract(j.value,'\$.msg') is not null order by j.key desc limit 1;" 2>/dev/null)
      last_state=${last%%,*}
      last_end=${last#*,}

      marker=0
      if [ "$last_state" = "3" ]; then
        marker=1
      fi
      if [ "$dur" -gt 0 ] && [ -n "$last_end" ]; then
        threshold=$((dur * 1000 - ENDTIME_TOLERANCE_MS))
        if [ "$last_end" -ge "$threshold" ] 2>/dev/null; then
          marker=1
        fi
      fi

      if [ "$marker" = "1" ] && [ "$len" -gt 0 ]; then
        marker_stable=$((marker_stable + 1))
      else
        marker_stable=0
      fi

      if [ "$marker_stable" -ge "$MARKER_STABLE_SECONDS" ]; then
        reason="marker"
        break
      fi
      if [ "$stable" -ge "$FALLBACK_STABLE_SECONDS" ]; then
        reason="stable"
        break
      fi

      waited=$((waited + 1))
      if [ "$waited" -gt 180 ]; then
        log "timeout id=$rid len=$len dur=$dur"
        reason="timeout"
        break
      fi
      sleep 1
    done

    if [ "$len" -le 0 ]; then
      log "skip empty id=$rid"
      last_id=$rid
      echo "$last_id" > "$ID_FILE"
      continue
    fi
    log "ready id=$rid reason=$reason len=$len dur=$dur"

    payload=$("$SQLITE3" -readonly "$SMARTANSWER_DB" "
      select json_object(
        'title', 'AI代接 · ' || coalesce(nullif(s.contact_name,''), s.number) ||
                 (case when s.during_time > 0 then ' · ' || s.during_time || 's' else '' end),
        'body', (
          select group_concat(line, char(10)) from (
            select (case when json_extract(j.value,'\$.isme')=2 then '[AI] ' else '[对方] ' end) ||
                   json_extract(j.value,'\$.msg') as line
            from json_each(s.chat_json) j
            where json_extract(j.value,'\$.msg') is not null
            order by j.key
          )
        ),
        'group','AI通话',
        'level','active',
        'isArchive',1
      )
      from smart_answer s where s._id=$rid;" 2>/dev/null)

    if [ -z "$payload" ]; then
      log "empty payload id=$rid"
      last_id=$rid
      echo "$last_id" > "$ID_FILE"
      continue
    fi

    code=$(printf '%s' "$payload" | "$CURL" -sS -m 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$BARK_URL" 2>>"$LOG")
    log "push id=$rid http=$code $payload"

    if [ "$code" = "200" ]; then
      last_id=$rid
      echo "$last_id" > "$ID_FILE"
    else
      log "push failed id=$rid, retry later"
      break
    fi
  done

  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
    tail -c $((LOG_MAX_BYTES / 2)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi

  sleep "$POLL_SECONDS"
done
