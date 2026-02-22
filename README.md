# OpenClaw Federation (Production Ready)

这是一套经过重构的生产级 OpenClaw 联邦部署工具。它允许你将多个设备（服务器、PC、树莓派）组成一个统一的 AI 智能体集群。

## 架构说明

OpenClaw 联邦采用 **Master-Worker** 架构，通过 Tailscale 安全内网互联。

| 角色 | 描述 | 适用场景 | 运行服务 |
|------|------|----------|----------|
| **Master (大脑)** | 联邦的主控节点。负责思考、记忆、管理会话和外部渠道（Telegram/WhatsApp）。 | VPS, 公网服务器, 常开的主力机 | `openclaw-gateway` |
| **Worker (手脚)** | 纯执行节点。不思考，仅提供本机能力（Shell执行、摄像头、屏幕）给 Master 调用。 | 树莓派, 家庭服务器, 备用机 | `openclaw-worker` (连接服务) |
| **Hybrid (混合)** | 高级模式。既保留本地大脑（可独立聊天），又作为手脚连接远程 Master。双进程隔离运行。 | 主力工作机 (MacBook/PC) | `openclaw-gateway` (本地) + `openclaw-worker` (远程连接) |

## 快速开始

### 1. 部署 Master (主控节点)

在你的 VPS 或主服务器上运行：

```bash
cd bin
./deploy-federation.sh master
```

*   脚本会自动安装 Tailscale 和 OpenClaw。
*   启动 Gateway 并生成 Admin Token。
*   **记录下脚本结束时显示的 Master Tailscale IP。**

### 2. 部署 Worker (工作节点)

在其他机器上运行（替换 `<MASTER_IP>` 为上一步获取的 IP）：

**场景 A：纯 Worker（推荐用于服务器/树莓派）**
此模式会**停止**本地原有的 Gateway，确保资源纯净。

```bash
cd bin
./deploy-federation.sh worker <MASTER_IP>
```

**场景 B：Hybrid 混合节点（推荐用于你的主力电脑）**
此模式**保留**你本地原有的 Gateway（你可以继续和它聊天），同时启动一个后台服务连接 Master。

```bash
cd bin
./deploy-federation.sh hybrid <MASTER_IP>
```

### 3. 批准节点加入

回到 **Master** 机器，批准新节点的连接请求。

**手动批准：**

```bash
cd bin
./manage-federation.sh pending        # 查看请求列表，获取 ID
./manage-federation.sh approve <ID>   # 批准加入
```

**自动批准（推荐用于批量部署）：**

```bash
cd bin
./auto-register.sh --watch
# 保持运行，它会自动批准所有新上线的 Worker
```

## 日常使用

所有管理操作都在 **Master** 节点上通过 `manage-federation.sh` 进行。

### 查看集群状态
```bash
./manage-federation.sh list
```

### 远程执行命令
让指定节点执行 Shell 命令：
```bash
./manage-federation.sh exec <节点名或ID> "uname -a"
./manage-federation.sh exec home-server "docker ps"
```

### 广播命令
让所有在线节点同时执行：
```bash
./manage-federation.sh broadcast "uptime"
```

### 智能体调用 (在聊天中)
你可以在 Telegram/WhatsApp 中直接对 Master 说：
> "让 home-server 检查一下磁盘空间"
> "在 macbook 上截个图发给我"

Master 会自动通过工具调用路由指令到对应的 Worker。

## 文件说明

*   `bin/deploy-federation.sh`: 核心部署脚本（支持 master/worker/hybrid 模式）。
*   `bin/manage-federation.sh`: Master 端管理工具（查看、批准、执行）。
*   `bin/auto-register.sh`: Master 端守护进程（自动批准 Worker 连接）。

## 故障排除

*   **连接不上？** 检查 Master 和 Worker 的 Tailscale 是否都 `Connected`。
*   **Hybrid 模式报错？** Hybrid 模式使用 `~/.openclaw-worker` 作为隔离目录，确保没有手动修改过该目录权限。
*   **查看日志：**
    *   Master: `openclaw gateway logs`
    *   Worker 服务: `sudo journalctl -u openclaw-worker -f`
