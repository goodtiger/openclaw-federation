# OpenClaw 联邦部署完整指南

> 多机 OpenClaw 联邦部署与管理的完整解决方案

---

## 📋 目录

- [概述](#概述)
- [架构说明](#架构说明)
- [快速开始](#快速开始)
- [详细部署](#详细部署)
- [工具说明](#工具说明)
- [使用示例](#使用示例)
- [故障排查](#故障排查)
- [安全建议](#安全建议)

---

## 概述

### 什么是 OpenClaw 联邦部署？

OpenClaw 联邦部署允许你将多台运行 OpenClaw 的机器组成一个集群：

- **Master 节点**：中央管理节点，协调所有 Worker
- **Worker 节点**：执行节点，各自拥有不同的技能（Docker、K8s、Apple Notes 等）
- **Tailscale 网络**：所有节点通过加密隧道安全互联

### 适用场景

- ✅ 家庭实验室（多设备协作）
- ✅ 跨平台自动化（Linux + Mac + Raspberry Pi）
- ✅ 技能互补（不同机器有不同技能）
- ✅ 分布式任务执行

### 不适用场景

- ❌ 单台机器（不需要联邦）
- ❌ 所有机器技能完全相同（浪费资源）

---

## 架构说明

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户 (Telegram/Discord)                   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Master 节点                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   Gateway   │◄──►│    Agent    │◄──►│   Command Router    │ │
│  │  (管理接口)  │    │  (调度中心)  │    │   (命令分发)        │ │
│  │  100.64.0.1 │    │             │    │                     │ │
│  └──────┬──────┘    └─────────────┘    └─────────────────────┘ │
│         │                                                        │
│    Tailscale 加密隧道                                             │
│         │                                                        │
└─────────┼────────────────────────────────────────────────────────┘
          │
    ┌─────┴─────┬─────────────┬─────────────┐
    │           │             │             │
    ▼           ▼             ▼             ▼
┌────────┐ ┌────────┐   ┌────────┐   ┌────────┐
│Worker1 │ │Worker2 │   │Worker3 │   │Worker4 │
│(Linux) │ │ (Mac)  │   │ (Pi)   │   │ (VPS)  │
├────────┤ ├────────┤   ├────────┤   ├────────┤
│Docker  │ │Apple   │   │GPIO    │   │Public  │
│K8s     │ │Notes   │   │Sensors │   │Services│
│Tmux    │ │Music   │   │Camera  │   │        │
└────────┘ └────────┘   └────────┘   └────────┘
```

### 通信流程

1. **用户**发送消息到 Master（Telegram/Discord）
2. **Master Agent**解析意图，决定由哪个 Worker 执行
3. **Master Gateway**通过 Tailscale 连接到目标 Worker
4. **Worker**在本地执行命令，返回结果
5. **Master**将结果返回给用户

---

## 快速开始

### 前提条件

- 所有机器已安装 OpenClaw
- 所有机器已加入同一个 Tailscale 网络
- 有 root/sudo 权限

### 一键部署

```bash
# 1. 在 Master 节点执行
sudo ./deploy-federation.sh master --bind-tailscale

# 2. 记录显示的 Token

# 3. 在 Worker 节点执行
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "复制Master显示的Token"
```

---

## 详细部署

### 第一步：准备所有节点

#### 安装 Tailscale（所有节点）

```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# macOS
brew install tailscale
sudo tailscale up

# 验证连接
tailscale status
tailscale ip -4
```

#### 安装 OpenClaw（所有节点）

```bash
# 安装 Node.js
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# 安装 OpenClaw
npm install -g openclaw

# 验证
openclaw version
```

### 第二步：部署 Master 节点

#### 选项 A：默认部署（0.0.0.0）

```bash
sudo ./deploy-federation.sh master
```

- 绑定 0.0.0.0（所有接口）
- 需要配置防火墙
- 本地调试方便

#### 选项 B：安全部署（推荐）

```bash
sudo ./deploy-federation.sh master --bind-tailscale
```

- 绑定 Tailscale IP（如 100.64.0.1）
- 仅 Tailscale 网络可访问
- 天然安全，无需防火墙

#### 选项 C：启用配置中心

```bash
sudo ./deploy-federation.sh master --bind-tailscale --enable-config-center
```

- 启用统一配置管理
- Worker 自动同步配置

部署完成后会显示：
```
[OK] Gateway 启动成功
Token: abc123def456...
保存位置: /root/.openclaw/.federation-token
```

**保存好这个 Token！**

### 第三步：部署 Worker 节点

#### Worker 部署命令

```bash
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "从Master复制的Token" \
  --node-name "worker1"
```

#### 可选：自动注册到 Master

```bash
# 部署后自动注册
sudo ./auto-register.sh

# 或指定 Master IP
sudo ./auto-register.sh 100.64.0.1
```

#### 可选：同步配置（如启用配置中心）

```bash
sudo ./config-center.sh worker sync
```

### 第四步：验证部署

#### 在 Master 上查看节点

```bash
openclaw nodes list
```

预期输出：
```
ID    Name      URL                      Status
─────────────────────────────────────────────────
n-xxx worker1   ws://100.64.0.2:18789    connected
n-yyy worker2   ws://100.64.0.3:18789    connected
```

#### 测试远程执行

```bash
# 在 worker1 上执行命令
openclaw nodes invoke worker1 -- uname -a

# 在 worker2 上执行 docker 命令
openclaw nodes invoke worker2 -- docker ps
```

---

## 工具说明

### 1. deploy-federation.sh（核心部署脚本）

**用途**：部署 Master 或 Worker 节点

**用法**：
```bash
# Master 部署
sudo ./deploy-federation.sh master [选项]

# Worker 部署
sudo ./deploy-federation.sh worker [选项]
```

**选项**：
| 选项 | 说明 | 适用 |
|------|------|------|
| `--bind-tailscale` | 绑定 Tailscale IP | Master/Worker |
| `--enable-config-center` | 启用配置中心 | Master |
| `--master-ip IP` | 指定 Master IP | Worker |
| `--token TOKEN` | 指定 Token | Worker |
| `--node-name NAME` | 节点名称 | Worker |
| `--skills "s1 s2"` | 安装技能 | Worker |

**示例**：
```bash
# Master 安全模式
sudo ./deploy-federation.sh master --bind-tailscale

# Worker 默认模式
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "xxx" \
  --node-name "home-server" \
  --skills "docker k8s"
```

### 2. health-check.sh（健康检查）

**用途**：监控所有节点健康状态

**用法**：
```bash
# 执行一次检查
sudo ./health-check.sh check

# 启动守护进程
sudo ./health-check.sh daemon

# 安装为系统服务
sudo ./health-check.sh install

# 查看状态
./health-check.sh status

# 查看日志
./health-check.sh logs
```

**配置**：
```bash
# 编辑配置文件
nano /root/.openclaw/.federation-health.conf

# 内容：
CHECK_INTERVAL=60      # 检查间隔（秒）
TIMEOUT=5              # 超时时间
FAIL_THRESHOLD=3       # 失败阈值
AUTO_REMOVE_UNHEALTHY=false  # 自动移除不健康节点
```

### 3. auto-register.sh（自动注册）

**用途**：Worker 自动向 Master 注册

**用法**：
```bash
# 自动发现 Master 并注册
sudo ./auto-register.sh

# 指定 Master IP
sudo ./auto-register.sh 100.64.0.1

# 指定 IP 和 Token
sudo ./auto-register.sh 100.64.0.1 "token"
```

### 4. config-center.sh（配置中心）

**用途**：统一管理和同步配置

**Master 端**：
```bash
# 启动配置服务
sudo ./config-center.sh master start

# 更新配置
sudo ./config-center.sh master update channels.telegram.enabled true

# 导出配置
./config-center.sh master export
```

**Worker 端**：
```bash
# 手动同步
sudo ./config-center.sh worker sync

# 启动自动同步守护进程
sudo ./config-center.sh worker daemon

# 查看与 Master 的差异
./config-center.sh worker diff
```

### 5. switch-bind-mode.sh（绑定模式切换）

**用途**：Worker 切换 Gateway 绑定模式

**用法**：
```bash
# 查看当前状态
./switch-bind-mode.sh status

# 切换到 0.0.0.0（开放模式）
sudo ./switch-bind-mode.sh to-all

# 切换到 Tailscale IP（安全模式）
sudo ./switch-bind-mode.sh to-tailscale

# 测试连��
./switch-bind-mode.sh test

# 回滚配置
./switch-bind-mode.sh rollback
```

**使用场景**：
- 部署时绑定 Tailscale IP（安全）
- 需要本地调试时 → 切换到 0.0.0.0
- 调试完成后 → 切回 Tailscale IP

### 6. config-manager.sh（配置管理）

**用途**：配置备份、恢复、合并

**用法**：
```bash
# 立即备份
./config-manager.sh backup

# 列出所有备份
./config-manager.sh list

# 恢复到最新备份
./config-manager.sh restore-latest

# 恢复到指定备份
./config-manager.sh restore openclaw.json.backup.20260221_143052

# 比较差异
./config-manager.sh diff openclaw.json.backup.20260221_143052
```

### 7. manage-federation.sh（节点管理）

**用途**：管理联邦节点，执行远程命令

**用法**：
```bash
# 列出所有节点
./manage-federation.sh list

# 在指定节点执行命令
./manage-federation.sh exec worker1 -- docker ps

# 广播到所有节点
./manage-federation.sh broadcast "uptime"

# 查找具有特定技能的节点
./manage-federation.sh find docker
```

---

## 使用示例

### 示例 1：家庭实验室部署

**场景**：家里有一台 Linux 服务器和一台 Mac

```bash
# Linux 服务器作为 Master
ssh linux-server
sudo ./deploy-federation.sh master --bind-tailscale

# Mac 作为 Worker
ssh mac
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "xxx" \
  --node-name "mac-mini" \
  --skills "apple-notes"

# 在 Master 上让 Mac 创建笔记
openclaw nodes invoke mac-mini -- \
  openclaw skill apple-notes --title "购物清单" --body "1. 牛奶\n2. 鸡蛋"
```

### 示例 2：混合云部署

**场景**：VPS + 家庭服务器

```bash
# VPS 作为 Master（公网可访问）
ssh vps
sudo ./deploy-federation.sh master --bind-tailscale

# 家庭服务器作为 Worker（内网）
ssh home-server
sudo ./deploy-federation.sh worker \
  --master-ip 100.64.0.1 \
  --token "xxx" \
  --skills "docker k8s"

# 在 VPS 上管理家庭服务器的 Docker
openclaw nodes invoke home-server -- docker ps
openclaw nodes invoke home-server -- kubectl get pods
```

### 示例 3：开发测试集群

**场景**：3 台 Raspberry Pi 组成测试集群

```bash
# Pi1 作为 Master
ssh pi1
sudo ./deploy-federation.sh master

# Pi2, Pi3 作为 Worker
for pi in pi2 pi3; do
  ssh $pi "sudo ./deploy-federation.sh worker \
    --master-ip 100.64.0.1 \
    --token \"xxx\" \
    --skills \"docker\""
done

# 在 Pi1 上管理整个集群
./manage-federation.sh broadcast "uptime"
./manage-federation.sh exec pi2 -- docker run -d nginx
```

### 示例 4：配置统一管理

**场景**：统一更新所有节点的 Telegram 配置

```bash
# 在 Master 上更新配置
sudo ./config-center.sh master update \
  channels.telegram.allowFrom '["5145113446", "1234567890"]'

# 所有 Worker 自动同步
# 或手动同步
for node in worker1 worker2 worker3; do
  ssh $node "sudo ./config-center.sh worker sync"
done
```

---

## 故障排查

### 问题 1：Worker 无法注册到 Master

**症状**：`openclaw nodes list` 看不到 Worker

**排查**：
```bash
# 1. 检查网络连通性
tailscale ping 100.64.0.2

# 2. 检查 Worker Gateway 是否运行
ssh worker
openclaw gateway status

# 3. 检查 Token 是否一致
cat ~/.openclaw/.federation-token

# 4. 手动测试连接
curl -H "Authorization: Bearer $TOKEN" \
  http://100.64.0.2:18789/health
```

**解决**：
```bash
# 重新注册
sudo ./auto-register.sh 100.64.0.1
```

### 问题 2：Master 无法访问 Worker

**症状**：`openclaw nodes invoke` 超时

**排查**：
```bash
# 1. 检查 Worker 绑定地址
ssh worker
jq '.gateway.bind' ~/.openclaw/openclaw.json

# 2. 如果绑定的是 100.64.0.x，确保使用 Tailscale IP
# 3. 如果绑定的是 0.0.0.0，检查防火墙
```

**解决**：
```bash
# 切换到 0.0.0.0（如需要本地访问）
sudo ./switch-bind-mode.sh to-all

# 或切换到 Tailscale IP（如需要安全）
sudo ./switch-bind-mode.sh to-tailscale
```

### 问题 3：配置同步失败

**症状**：Worker 配置未更新

**排查**：
```bash
# 查看配置差异
./config-center.sh worker diff

# 检查 Master 配置中心是否运行
ssh master
./config-center.sh master status
```

**解决**：
```bash
# 手动同步
sudo ./config-center.sh worker sync

# 或重启配置中心
ssh master
sudo ./config-center.sh master restart
```

### 问题 4：Token 泄露或需要更换

**解决**：
```bash
# 1. 在 Master 上重新生成 Token
rm /root/.openclaw/.federation-token
sudo ./deploy-federation.sh master

# 2. 将新 Token 复制到所有 Worker
for worker in worker1 worker2 worker3; do
  scp /root/.openclaw/.federation-token $worker:/root/.openclaw/
  ssh $worker "openclaw gateway restart"
done
```

---

## 安全建议

### 1. 网络安全

```bash
# Master 使用 Tailscale 绑定（推荐）
sudo ./deploy-federation.sh master --bind-tailscale

# 如果 Master 使用 0.0.0.0，配置防火墙
sudo ufw allow from 100.64.0.0/10 to any port 18789
sudo ufw deny 18789/tcp
```

### 2. Token 安全

- Token 文件权限：`chmod 600 ~/.openclaw/.federation-token`
- 定期更换 Token
- 不要明文传输 Token（使用 SSH 或安全通道）

### 3. 配置安全

- 定期备份配置：`./config-manager.sh backup`
- 敏感信息（如 Telegram Bot Token）使用配置中心统一管理

### 4. 节点安全

- Worker 默认绑定 0.0.0.0 时，确保内网可信
- 生产环境 Worker 也建议使用 `--bind-tailscale`

---

## 文件清单

| 文件 | 用途 | 必需 |
|------|------|------|
| `deploy-federation.sh` | 核心部署脚本 | ✅ |
| `health-check.sh` | 健康检查 | 可选 |
| `auto-register.sh` | 自动注册 | 可选 |
| `config-center.sh` | 配置中心 | 可选 |
| `switch-bind-mode.sh` | 绑定切换 | 可选 |
| `config-manager.sh` | 配置管理 | 可选 |
| `manage-federation.sh` | 节点管理 | 可选 |

---

## 更新日志

### v1.0 - 基础功能
- ✅ 联邦部署脚本
- ✅ Token 共享机制
- ✅ 配置备份/恢复

### v2.0 - 高级功能
- ✅ 健康检查系统
- ✅ 自动注册机制
- ✅ 配置中心
- ✅ 绑定模式切换
- ✅ Worker 默认 0.0.0.0

---

## 许可证

MIT License

---

**遇到问题？** 查看 `demo-*.sh` 脚本获取更多示例！
