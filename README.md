# vivo-ai-call-bark

把 vivo / iQOO「小V电话助手（AI 通话代接）」挂机后的**完整对话**推送到 Bark / iOS。

> 不是通话中实时逐句。vivo 在通话过程中不写数据库，挂机后云端 ASR 完成后才把 `chat_json` 写入 `smartdatabase.db`。脚本会在转写稳定后推一条完整记录。

## 背景

vivo 自带的「互传」和 iPhone 的「双机互联」都无法把 AI 通话记录（小V电话助手代接的对话/录音）传到 iPhone。SmsForwarder 也只能转发普通短信和来电通知，拿不到 AI 代接的对话正文。

所以做了这个脚本：从 vivo 的私有数据库读取完整转写，挂机后通过 Bark 推送到 iOS。

## 效果

Bark 通知：

**标题**

```
AI代接 · 示例联系人 · 46s
```

**正文**

```
[AI] 您好，请问您有什么事情？
[对方] 喂，你好
[AI] 我是他的电话助手，您继续说。
[对方] 哦，我有这个体检方面的事情跟他沟通，请他接一下电话
[AI] 好的，我会转告他尽快回电您，您还有其他事吗？
[对方] 嗯，没有了谢谢
```

一条完整记录，不逐句刷屏。

## 功能

- 每次 AI 代接只推一条完整对话
- 自动判断转录完成：最后一条 `state=3`，或 `endTime` 接近 `during_time`，再等 5 秒
- 异常情况回退到 12 秒长度稳定判断
- 优先读 `config` 里的 `BARK_URL`，也可以复用 SmsForwarder 的 Bark 通道
- 提供 `install / start / stop / status / uninstall` 脚本
- 支持 Magisk / KernelSU `service.d` 开机自启
- 日志、状态、失败重试

## 原理

```
小V电话助手
   └─ 写入 /data/data/com.vivo.smartanswer/databases/smartdatabase.db
         表 smart_answer，字段 chat_json
              │
              ▼
        full_push.sh（root）
         ├─ 轮询新记录
         ├─ 等待转录完成
         ├─ 拼成完整对话
         └─ curl POST → Bark → iPhone
```

## 适用设备

- 已验证：vivo X Flip（V2256A / PD2256），Android 16，系统 `PD2256C_A_16.3.16.0.W10`
- 其他 vivo / iQOO 机型，只要系统里有 `com.vivo.smartanswer` 且表结构一致，理论上可用
- 其他品牌（小米 / 华为 / OPPO）不适用，它们的 AI 通话存储方式不同

## 前提

1. **root**（Magisk / KernelSU / 临时 root 均可）
2. `sqlite3` 和 `curl`。多数 vivo 系统自带；没有就装 Termux，脚本会自动找 Termux 的路径
3. Bark App 和一个 Device Key
4. 手机开启了「小V电话助手」的自动代接

> 没有 root 就用不了：`/data/data/com.vivo.smartanswer` 是应用私有目录。没有 root 时只能用 SmsForwarder 转发“小V已自动接听 xxx 的来电”的通知，拿不到对话正文。

## 安装

### 方式一：adb（推荐）

```bash
adb push vivo-ai-call-bark /data/local/tmp/
adb shell
su
sh /data/local/tmp/vivo-ai-call-bark/install.sh
```

编辑配置：

```bash
vi /data/adb/ai-call-watch/config
```

把 `BARK_URL` 改成你自己的：

```sh
BARK_URL="https://api.day.app/你的DeviceKey/"
```

如果手机上没有 `vi`，可以在电脑上改：

```bash
adb pull /data/adb/ai-call-watch/config
# 编辑 config
adb push config /data/adb/ai-call-watch/config
```

启动：

```bash
sh /data/adb/ai-call-watch/start.sh
sh /data/adb/ai-call-watch/status.sh
```

### 方式二：在手机上直接装

把项目文件夹放到 `/sdcard/Download/`，用 Termux：

```bash
su -c 'sh /sdcard/Download/vivo-ai-call-bark/install.sh'
su -c 'vi /data/adb/ai-call-watch/config'
su -c 'sh /data/adb/ai-call-watch/start.sh'
```

## 配置说明

配置文件：`/data/adb/ai-call-watch/config`

| 配置 | 说明 |
|---|---|
| `BARK_URL` | Bark 推送地址；必填，或留空走 SmsForwarder |
| `SMS_FORWARDER_DB` | SmsForwarder 数据库路径，用于自动读取 Bark 地址 |
| `SMARTANSWER_DB` | 小V电话助手数据库路径 |
| `WATCH_DIR` | 安装 / 状态 / 日志目录，默认 `/data/adb/ai-call-watch` |
| `POLL_SECONDS` | 轮询间隔，默认 5 秒 |
| `MARKER_STABLE_SECONDS` | 命中完成标记后再等几秒，默认 5 |
| `FALLBACK_STABLE_SECONDS` | 没有完成标记时的稳定等待，默认 12 |
| `ENDTIME_TOLERANCE_MS` | `endTime` 与 `during_time` 的容差，默认 4000ms |

如果不想用 SmsForwarder，只填 `BARK_URL` 即可，`SMS_FORWARDER_DB` 可以忽略。

## 测试

1. 用**未保存到通讯录**的号码拨打这台手机（联系人代接默认可能是关闭的）
2. 响铃几秒，等小V接起来，随便说几句，挂断
3. 等待 30–60 秒
4. 查看日志：

```bash
su -c 'tail -20 /data/adb/ai-call-watch/full.log'
```

应该能看到：

```
ready id=139 reason=marker len=962 dur=14
push id=139 http=200 {"title":"AI代接 · 示例联系人","body":"[AI] ...\n[对方] ..."}
```

5. iPhone 上应该收到一条 Bark 通知。

### 直接测试 Bark

```bash
curl -sS -X POST "https://api.day.app/你的DeviceKey/" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Bark test","body":"hello"}'
```

返回 `{"code":200,...}` 就说明通道正常。

## 开机自启

### Magisk / KernelSU

安装脚本已经把自启脚本放到：

```
/data/adb/ai-call-watch/service.d/99-vivo-ai-call-bark.sh
```

复制到 `service.d`：

```bash
su -c 'cp /data/adb/ai-call-watch/service.d/99-vivo-ai-call-bark.sh /data/adb/service.d/'
su -c 'chmod 755 /data/adb/service.d/99-vivo-ai-call-bark.sh'
```

### Termux:Boot

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/ai-call-bark.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
until su -c true 2>/dev/null; do sleep 30; done
su -c 'sh /data/adb/ai-call-watch/start.sh'
EOF
chmod +x ~/.termux/boot/ai-call-bark.sh
```

### 临时 root

如果用的是临时 root（例如 DirtyFrag），重启后 root 失效，脚本也会停。重新 root 后执行：

```bash
su -c 'sh /data/adb/ai-call-watch/start.sh'
```

## 常用命令

```bash
# 启动
su -c 'sh /data/adb/ai-call-watch/start.sh'

# 停止
su -c 'sh /data/adb/ai-call-watch/stop.sh'

# 状态 + 最近日志
su -c 'sh /data/adb/ai-call-watch/status.sh'

# 实时看日志
su -c 'tail -f /data/adb/ai-call-watch/full.log'
```

## 补推历史

脚本首次启动只处理当前最新记录之后的新通话。如果想补推某条：

```bash
# 例如当前 last_id=139，想看 135 之后的所有记录
su -c 'echo 134 > /data/adb/ai-call-watch/full_last_id'
su -c 'sh /data/adb/ai-call-watch/stop.sh'
su -c 'sh /data/adb/ai-call-watch/start.sh'
```

注意：这会把这些记录全部推到 Bark，可能很吵。

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 启动失败，`must run as root` | 没用 `su` | 用 `su -c 'sh start.sh'` |
| `cannot read ...smartdatabase.db` | 没有 root / 没有小V电话助手 | 确认 root；确认系统里有 `com.vivo.smartanswer` |
| `schema mismatch` | 系统版本不同，表结构变了 | 用 `sqlite3 ... '.schema smart_answer'` 看字段，提 issue |
| `sqlite3 not found` | 系统没带 sqlite3 | 装 Termux；在 config 里设 `SQLITE3=/data/data/com.termux/files/usr/bin/sqlite3` |
| `curl not found` | 系统没带 curl | 装 Termux；在 config 里设 `CURL=...` |
| `push http=000` | 网络 / Bark 地址错误 | 先手动 `curl` 测试 Bark |
| `http=200` 但 iPhone 没通知 | Bark Key 错 / 通知权限 | 在 Bark App 里检查 |
| 有记录但没推送 | 脚本没运行 / `last_id` 已推进 | `status.sh`；必要时调小 `full_last_id` |
| 电话响了但 AI 没接 | 联系人代接关闭 / 账号未登录 / 非陌生号码 | 打开联系人代接，或换未保存号码；检查 vivo 账号 |
| 重启后失效 | 临时 root | 重新 root 后 `start.sh`；或换永久 root + service.d |

## 限制

- 只处理 **AI 代接** 的通话；用户自己接的电话没有记录
- 转写是在挂机后由云端生成的，所以无法做到通话中逐句
- 依赖 vivo 的私有数据库结构，系统升级后可能需要适配
- 只实现了 Bark；其他推送通道可以改 `curl` 部分
- 通话内容会经过 Bark 服务器（官方 `api.day.app` 或你自建的 bark-server）

## 隐私

这个脚本会把**完整通话转写**发送到 Bark。请：

- 使用自己的 Bark Key，不要用别人的
- 不要把 `config`、`full.log`、`full_last_id` 提交到 Git 或发给别人
- 在需要录音 / 转写的场景遵守当地法律和对方知情同意

## 卸载

```bash
su -c 'sh /data/adb/ai-call-watch/uninstall.sh'
```

或手动：

```bash
su -c 'sh /data/adb/ai-call-watch/stop.sh'
su -c 'rm -rf /data/adb/ai-call-watch'
```

## 目录

```
vivo-ai-call-bark/
├── full_push.sh
├── start.sh
├── stop.sh
├── status.sh
├── install.sh
├── uninstall.sh
├── config.example
├── service.d/
│   └── 99-vivo-ai-call-bark.sh
├── README.md
├── LICENSE
└── .gitignore
```

## License

MIT
