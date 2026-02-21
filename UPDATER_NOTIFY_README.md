# OpenClaw 自动更新提醒

当 OpenClaw 有新版本发布时，自动发送 Telegram 通知。

## 快速设置

```bash
# 1. 运行安装脚本
/root/.openclaw/workspace/install-updater-notify.sh

# 2. 按提示选择检查频率即可
```

## 手动设置（高级）

### 1. 添加到 Cron

```bash
crontab -e
```

添加以下行之一：

```bash
# 每天早上 9 点检查
0 9 * * * /usr/bin/python3 /root/.openclaw/workspace/openclaw-updater-notify.py >> /tmp/openclaw-notify.log 2>&1

# 每天两次（早上9点、晚上9点）
0 9,21 * * * /usr/bin/python3 /root/.openclaw/workspace/openclaw-updater-notify.py >> /tmp/openclaw-notify.log 2>&1

# 每小时检查
0 * * * * /usr/bin/python3 /root/.openclaw/workspace/openclaw-updater-notify.py >> /tmp/openclaw-notify.log 2>&1
```

### 2. 测试运行

```bash
python3 /root/.openclaw/workspace/openclaw-updater-notify.py
```

### 3. 查看日志

```bash
tail -f /tmp/openclaw-notify.log
```

## 工作原理

1. **检查 GitHub Release** - 获取最新版本号
2. **对比本地版本** - 判断是否有更新
3. **去重通知** - 每个新版本只通知一次（通过状态文件记录）
4. **发送 Telegram** - 使用 `openclaw message send` 命令

## 状态文件

```
/root/.openclaw/workspace/.openclaw-checker-state.json
```

包含上次通知的版本号，避免重复通知。

## 通知示例

```
🎉 OpenClaw 更新提醒

发现新版本: v2026.2.20
当前版本: 2026.2.19-2

📋 更新摘要:
- iOS/Watch: add Apple Watch support
- Security: fix vulnerability in gateway auth
...

🔗 详情: https://github.com/openclaw/openclaw/releases/tag/v2026.2.20

💻 升级命令:
pm update -g openclaw
```

## 常见问题

### Q: 为什么没收到通知？
- 检查日志：`tail /tmp/openclaw-notify.log`
- 确认 Telegram 配置正确
- 检查是否已经有最新版本

### Q: 如何重置通知状态？
```bash
rm /root/.openclaw/workspace/.openclaw-checker-state.json
```

### Q: 如何临时禁用？
```bash
# 注释掉 crontab 中的相关行
crontab -e
```

## 文件清单

| 文件 | 说明 |
|------|------|
| `openclaw-updater-notify.py` | 自动提醒主程序 |
| `install-updater-notify.sh` | 交互式安装脚本 |
| `.openclaw-checker-state.json` | 状态文件（自动生成） |

## 相关工具

- `openclaw-checker.py` - 完整版检查工具（带彩色输出）
- `openclaw-checker.sh` - Bash 轻量版
