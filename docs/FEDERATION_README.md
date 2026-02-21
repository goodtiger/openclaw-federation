# OpenClaw + Tailscale 联邦部署指南

一键部署多机 OpenClaw 联邦环境，所有机器通过 Tailscale 虚拟网络互联，实现技能共享和任务分发。

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale 虚拟网络 (100.x.x.x)            │
│                                                             │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│   │  VPS     │◄──►│家庭服务器 │◄──►│   Mac    │             │
│   │(主控节点)│    │(Docker)  │    │(Apple)   │             │
│   │100.64.0.1│    │100.64.0.2 │    │100.64.0.3 │             │
│   └────┬─────┘    └────┬─────┘    └────┬─────┘             │
│        │               │               │                    │
│        └───────────────┴───────────────┘                    │
│                        │                                    │
│                   技能共享/任务分发                          │
└─────────────────────────────────────────────────────────────┘
```

## 快速开始

### 1. 准备

- 所有机器安装好 Linux/macOS
- 确保能访问互联网
- 准备一个 Tailscale 账号（免费）

### 2. 部署主节点（VPS/公网服务器）

```bash
# 下载部署脚本
curl -fsSL -o deploy.sh https://your-server/deploy-openclaw-federation.sh
chmod +x deploy.sh

# 部署主节点
sudo ./deploy.sh master
```

部署完成后会显示：
- Tailscale IP（如 100.64.0.1）
- 共享 Token（其他机器需要）

**保存好这个 Token！**

### 3. 部署工作节点

在家庭服务器、Mac、Pi 等机器上执行：

```bash
# 下载脚本
curl -fsSL -o deploy.sh https://your-server/deploy-openclaw-federation.sh
chmod +x deploy.sh

# 部署工作节点（替换 IP 和 Token）
sudo ./deploy.sh worker \
  --master-ip 100.64.0.1 \
  --node-name home-server \
  --skills "docker k8s tmux"
```

参数说明：
- `--master-ip`: 主节点的 Tailscale IP
- `--node-name`: 给这个节点起个名字
- `--skills`: 要安装的技能（可选）

### 4. 在主节点添加工作节点

```bash
# 使用管理脚本
./manage-federation.sh add home-server 100.64.0.2 "docker k8s"
./manage-federation.sh add mac-pc 100.64.0.3 "apple-notes"
```

或者手动添加：
```bash
openclaw pair approve \
  --name home-server \
  --url "ws://100.64.0.2:18789" \
  --token "你的Token"
```

### 5. 验证

```bash
# 查看所有节点
./manage-federation.sh list

# 测试连接
./manage-federation.sh exec home-server uname -a
./manage-federation.sh exec mac-pc uname -a

# 广播命令到所有节点
./manage-federation.sh broadcast docker ps
```

## 管理命令

### 节点管理

```bash
# 列出所有节点
./manage-federation.sh list

# 查看状态
./manage-federation.sh status

# 添加节点
./manage-federation.sh add <名称> <IP> [技能]

# 查找具有特定技能的节点
./manage-federation.sh find docker
```

### 远程执行

```bash
# 在指定节点执行命令
./manage-federation.sh exec home-server docker ps
./manage-federation.sh exec mac-pc openclaw skill apple-notes --list

# 广播到所有节点
./manage-federation.sh broadcast uptime
```

## 使用场景示例

### 场景 1：跨机器记笔记

你在 Telegram 上说：
```
在 Mac 上记个笔记：记得买牛奶
```

主控 Agent 执行：
```bash
openclaw nodes invoke mac-pc --message "用 Apple Notes 记: 记得买牛奶"
```

### 场景 2：在服务器上部署

```
在家庭服务器上部署 nginx
```

主控 Agent 执行：
```bash
openclaw nodes invoke home-server -- docker run -d -p 80:80 nginx
```

### 场景 3：Pi 控制硬件

```
让 Pi 读取温度传感器
```

主控 Agent 执行：
```bash
openclaw nodes invoke pi-device -- python3 /home/pi/read_sensor.py
```

## 手动配置（如果不想用脚本）

### 安装 Tailscale

```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# macOS
brew install tailscale
sudo tailscale up
```

### 配置 OpenClaw

编辑 `~/.openclaw/openclaw.json`：

```json
{
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.x",
    "auth": {
      "mode": "token",
      "token": "你的统一Token"
    }
  }
}
```

### 启动并连接

```bash
# 每台机器
openclaw gateway restart

# 在主节点添加其他节点
openclaw pair approve --name node1 --url ws://100.64.0.2:18789 --token xxx
```

## 安全建议

1. **Token 保密**: 所有机器使用相同的 Token，不要泄露
2. **Tailscale ACL**: 配置 Tailscale ACL 规则限制设备间访问
3. **防火墙**: 即使在内网，也建议只开放必要的端口
4. **定期更新**: 保持 OpenClaw 和 Tailscale 更新

## 故障排除

### Tailscale 连接不上

```bash
# 检查状态
tailscale status

# 重新登录
tailscale logout
tailscale up

# 测试连通性
tailscale ping 100.64.0.x
```

### Gateway 启动失败

```bash
# 检查配置
openclaw config validate

# 查看日志
openclaw gateway logs

# 手动启动看错误
openclaw gateway start --foreground
```

### 节点连接失败

```bash
# 在主节点测试连通性
tailscale ping <工作节点IP>
curl -H "Authorization: Bearer <token>" http://<IP>:18789/health

# 查看节点状态
openclaw nodes status

# 重新添加节点
openclaw nodes remove <节点名>
openclaw pair approve --name <节点名> --url ws://<IP>:18789 --token <token>
```

## 文件清单

| 文件 | 说明 |
|------|------|
| `deploy-openclaw-federation.sh` | 一键部署脚��� |
| `manage-federation.sh` | 节点管理脚本 |
| `FEDERATION_README.md` | 本文档 |

## 进阶配置

### 自动技能发现

未来可以实现：工作节点启动时自动上报自己的技能到主节点。

### 负载均衡

多台相同技能的机器可以组成池，任务自动分发。

### 故障转移

主节点宕机时，工作节点可以自动选举新主节点。

---

有问题？查看 [OpenClaw 文档](https://docs.openclaw.ai) 或加入 [Discord](https://discord.com/invite/clawd)
