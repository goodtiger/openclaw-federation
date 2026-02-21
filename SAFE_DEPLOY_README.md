# OpenClaw 联邦部署 - 安全配置指南

如何在已有 OpenClaw 的服务器上安全部署联邦功能，**不损坏现有配置**。

---

## 🛡️ 安全特性

### 新版部署脚本 (`deploy-federation-safe.sh`) 的保护机制：

1. **自动备份** - 部署前自动备份现有配置
2. **智能合并** - 使用 jq 安全合并配置，只修改 gateway 部分
3. **交互确认** - 检测到现有配置时会询问是否继续
4. **紧急恢复** - 提供一键恢复工具

---

## 📋 部署前检查清单

### 1. 备份当前配置（强烈推荐）

```bash
# 使用配置管理工具备份
/root/.openclaw/workspace/config-manager.sh backup

# 或手动备份
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.backup.$(date +%Y%m%d_%H%M%S)
```

### 2. 查看现有配置

```bash
# 查看配置中的关键设置
jq '{channels: (.channels | keys), models: .models, gateway: .gateway}' ~/.openclaw/openclaw.json

# 或查看完整配置
cat ~/.openclaw/openclaw.json | less
```

### 3. 记录重要设置

特别注意以下配置（部署后会保留）：
- `channels` - Telegram/Discord 等消息通道
- `models` - AI 模型配置
- `tools` - 工具设置（Web 搜索等）
- `agents` - Agent 设置
- `bindings` - 通道绑定

---

## 🚀 安全部署流程

### 主节点（VPS）部署

```bash
sudo /root/.openclaw/workspace/deploy-federation-safe.sh master
```

**部署过程中会：**
1. 检测到现有配置并显示预览
2. 询问是否继续
3. 自动备份到 `~/.openclaw/.backups/`
4. 使用 jq 合并配置（保留所有原有设置）

### 工作节点部署

```bash
sudo /root/.openclaw/workspace/deploy-federation-safe.sh worker \
  --master-ip 100.64.0.1 \
  --node-name home-server \
  --skills "docker k8s"
```

---

## 📁 配置管理工具

### 备份管理

```bash
# 立即备份
./config-manager.sh backup

# 列出所有备份
./config-manager.sh list

# 输出示例：
# 序号  备份文件                                时间                 大小
# ─────────────────────────────────────────────────────────────────────
# 1     openclaw.json.backup.20260221_143052    2026-02-21 14:30:52  4.0K
# 2     openclaw.json.backup.20260221_140015    2026-02-21 14:00:15  3.8K
```

### 恢复配置

```bash
# 恢复到最新备份
./config-manager.sh restore-latest

# 恢复到指定备份
./config-manager.sh restore openclaw.json.backup.20260221_143052

# 查看差异后再恢复
./config-manager.sh diff openclaw.json.backup.20260221_143052
./config-manager.sh restore openclaw.json.backup.20260221_143052
```

### 高级：交互式合并

如果联邦部署后丢失了某些配置，可以智能合并：

```bash
# 交互式合并：保留当前 gateway，恢复其他设置
./config-manager.sh merge openclaw.json.backup.20260221_143052

# 过程：
# 1. 显示备份和当前配置对比
# 2. 询问是否继续
# 3. 合并后保留联邦 gateway 设置
# 4. 恢复其他所有配置
```

---

## 🔧 常见问题

### Q: 部署后发现某些功能不正常了？

**A:** 立即恢复：
```bash
# 查看最新备份
./config-manager.sh list

# 恢复
./config-manager.sh restore-latest

# 重启 Gateway
openclaw gateway restart
```

### Q: 如何保留联邦功能的同时恢复其他配置？

**A:** 使用合并功能：
```bash
# 部署前备份
./config-manager.sh backup
# 备份文件名: openclaw.json.backup.before-federation

# 部署联邦（这会修改配置）
sudo ./deploy-federation-safe.sh master

# 发现需要恢复某些设置，但保留联邦 gateway
./config-manager.sh merge openclaw.json.backup.before-federation
# 这会：保留新的 gateway（联邦），恢复其他所有设置

# 重启生效
openclaw gateway restart
```

### Q: 脚本提示缺少 jq 怎么办？

**A:** 安装 jq 获得最佳体验：
```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# macOS
brew install jq
```

如果不安装 jq，脚本会：
- 创建基础配置
- 完整备份原配置
- 提示你手动合并

### Q: 如何查看备份和当前配置的区别？

```bash
# 对比指定备份
./config-manager.sh diff openclaw.json.backup.20260221_143052

# 或使用系统 diff
diff ~/.openclaw/.backups/openclaw.json.backup.xxx ~/.openclaw/openclaw.json
```

---

## 📊 配置安全流程图

```
部署前
  │
  ├── 1. 自动备份现有配置 ──► ~/.openclaw/.backups/
  │
  ├── 2. 显示配置预览
  │      └── channels, models, tools 等
  │
  ├── 3. 询问确认
  │      └── 用户输入 Y 继续
  │
  ├── 4. 智能合并（有 jq）
  │      ├── 保留: channels, models, tools, agents...
  │      └── 更新: gateway（联邦设置）
  │
  └── 5. 部署完成
         └── 显示恢复帮助

如果出问题
  │
  ├── 方法 1: 完全恢复
  │      ./config-manager.sh restore-latest
  │
  ├── 方法 2: 智能合并
  │      ./config-manager.sh merge <备份>
  │
  └── 方法 3: 手动编辑
         nano ~/.openclaw/openclaw.json
```

---

## 📝 文件清单

| 文件 | 说明 |
|------|------|
| `deploy-federation-safe.sh` | 安全部署脚本（保留配置） |
| `config-manager.sh` | 配置管理工具（备份/恢复/合并） |
| `deploy-openclaw-federation.sh` | 原版部署脚本（会覆盖配置）⚠️ |

**推荐：** 使用 `deploy-federation-safe.sh` 替代原版脚本

---

## ⚡ 快速参考

```bash
# 1. 备份（任何操作前都建议执行）
./config-manager.sh backup

# 2. 安全部署
sudo ./deploy-federation-safe.sh master
sudo ./deploy-federation-safe.sh worker --master-ip 100.64.0.1 --node-name server1

# 3. 如果出问题，恢复
./config-manager.sh restore-latest
openclaw gateway restart

# 4. 查看所有备份
./config-manager.sh list

# 5. 清理旧备份（保留最近10个）
./config-manager.sh clean
```

---

有问题？先备份，再操作！🛡️
