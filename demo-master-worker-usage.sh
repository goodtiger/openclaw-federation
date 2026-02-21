#!/bin/bash
#
# Master 调用 Worker 技能示例
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Master 调用 Worker 技能 - 实战示例                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
ok() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
log() { echo -e "${BLUE}[示例]${NC} $1"; }

echo "═══════════════════════════════════════════════════════════"
echo "【架构回顾】Master 如何调用 Worker 技能"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "拓扑结构:"
echo ""
echo "          用户 (Telegram)"
echo "               │"
echo "               ▼"
echo "    ┌─────────────────────┐"
echo "    │      Master         │"
echo "    │  ┌───────────────┐  │"
echo "    │  │    Agent      │  │  ← 接收用户消息"
echo "    │  │  (调度中心)    │  │"
echo "    │  └───────┬───────┘  │"
echo "    │          │          │"
echo "    │     openclaw        │"
echo "    │   nodes invoke      │"
echo "    │          │          │"
echo "    │  ┌───────▼───────┐  │"
echo "    │  │    Gateway    │  │  ← 通过 Tailscale"
echo "    │  │  (100.64.0.1) │  │     连接到 Worker"
echo "    │  └───────┬───────┘  │"
echo "    └──────────┼──────────┘"
echo "               │ WS/Tailscale"
echo "    ┌──────────┼──────────┐"
echo "    │          │          │"
echo "    ▼          ▼          ▼"
echo "┌────────┐ ┌────────┐ ┌────────┐"
echo "│ Worker1│ │ Worker2│ │ Worker3│"
echo "│(Docker)│ │  (Mac) │ │  (Pi)  │"
echo "└────────┘ └────────┘ └────────┘"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 1】基础命令执行"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：在 Worker 上查看系统信息"
echo ""

echo "命令:"
echo "  openclaw nodes invoke home-server -- uname -a"
echo ""

log "执行流程:"
echo "  1. Master 接收到命令"
echo "  2. 通过 Tailscale 连接到 home-server (100.64.0.2:18789)"
echo "  3. 在 Worker 上执行 uname -a"
echo "  4. 返回结果给 Master"
echo ""

ok "预期输出:"
echo "  Linux home-server 5.15.0-xx-generic #xx SMP x86_64 GNU/Linux"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 2】使用 Worker 的 Docker 技能"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：Worker1 有 Docker，Master 让它部署 Nginx"
echo ""

echo "命令:"
echo "  openclaw nodes invoke home-server -- docker run -d -p 80:80 nginx"
echo ""

log "执行流程:"
echo "  1. Master 发送 docker 命令到 home-server"
echo "  2. Worker1 在本机执行 docker run"
echo "  3. 容器在 Worker1 上启动"
echo "  4. 返回容器 ID"
echo ""

ok "预期输出:"
echo "  3a8f2c1d4e5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
echo ""

warn "注意：容器运行在 Worker1 上，不在 Master 上！"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 3】使用 Worker 的 K8s 技能"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：Worker2 有 Kubernetes，Master 让它查看 Pod"
echo ""

echo "命令:"
echo "  openclaw nodes invoke k8s-node -- kubectl get pods -n default"
echo ""

log "执行流程:"
echo "  1. Master 发送 kubectl 命令到 k8s-node"
echo "  2. Worker2 在本机执行 kubectl"
echo "  3. 连接到 Worker2 可访问的 K8s 集群"
echo "  4. 返回 Pod 列表"
echo ""

ok "预期输出:"
echo "  NAME                    READY   STATUS    RESTARTS   AGE"
echo "  nginx-7854ff8877-2xzp9   1/1     Running   0          5m"
echo "  app-6b8d9c7f5-4k2m1      1/1     Running   0          10m"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 4】使用 Mac Worker 的 Apple Notes"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：Mac 有 apple-notes 技能，Master 让它创建笔记"
echo ""

echo "命令:"
echo "  openclaw nodes invoke mac-pc --message \"创建笔记：记得买牛奶\""
echo ""

echo "或者使用 skill 命令:"
echo "  openclaw nodes invoke mac-pc -- openclaw skill apple-notes \\"
echo "    --title \"待办事项\" \\"
echo "    --body \"1. 买牛奶\\n2. 取快递\""
echo ""

log "执行流程:"
echo "  1. Master 发送命令到 mac-pc"
echo "  2. Worker (Mac) 调用 apple-notes skill"
echo "  3. 在 Mac 的 Apple Notes 中创建笔记"
echo "  4. 返回成功状态"
echo ""

ok "结果："
echo "  Mac 的 Apple Notes 应用中出现新笔记"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 5】通过 Agent 智能调度"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：用户在 Telegram 上说一句话，Master 自动调度"
echo ""

warn "用户消息: \"在家庭服务器上部署一个 nginx\""
echo ""

log "Master Agent 的处理流程:"
echo ""
echo "  1. 解析用户意图"
echo "     → 动作: 部署 nginx"
echo "     → 目标: 家庭服务器"
echo ""
echo "  2. 查找节点"
echo "     → 发现 home-server (100.64.0.2)"
echo "     → 检查技能: [docker, k8s, tmux] ✅"
echo ""
echo "  3. 执行命令"
echo "     → openclaw nodes invoke home-server -- docker run -d nginx"
echo ""
echo "  4. 返回结果给用户"
echo "     → \"已在 home-server 上部署 nginx，访问 http://home-server:80\""
echo ""

ok "用户感知：就像 Master 直接执行的一样！"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【示例 6】广播命令到所有 Worker"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "场景：更新所有节点的系统时间"
echo ""

echo "使用 manage-federation.sh:"
echo "  ./manage-federation.sh broadcast \"date -s '2026-02-21 10:00:00'\""
echo ""

echo "或者逐个调用:"
echo "  for node in home-server mac-pc pi-device; do"
echo "    openclaw nodes invoke \$node -- date -s '2026-02-21 10:00:00'"
echo "  done"
echo ""

log "执行效果:"
echo "  [home-server] 时间已更新"
echo "  [mac-pc] 时间已更新"
echo "  [pi-device] 时间已更新"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【完整命令参考】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "1. 基础命令执行"
echo "   openclaw nodes invoke <节点名> -- <命令>"
echo ""

echo "2. 带引号的命令"
echo "   openclaw nodes invoke home-server -- bash -c 'docker ps | grep nginx'"
echo ""

echo "3. 使用 OpenClaw skill"
echo "   openclaw nodes invoke <节点> -- openclaw skill <技能名> <参数>"
echo ""

echo "4. 交互式命令"
echo "   openclaw nodes invoke home-server -- tmux new-session -d -s mysession"
echo ""

echo "5. 文件传输 + 执行"
echo "   # 先传输文件"
echo "   scp script.sh home-server:/tmp/"
echo "   # 再执行"
echo "   openclaw nodes invoke home-server -- bash /tmp/script.sh"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【关键理解】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "1. Master 的 Gateway 和 Agent 是分开的:"
echo ""
echo "   Master Gateway (100.64.0.1:18789)"
echo "      ↑ 接收外部连接 (Telegram/User)"
echo "      │"
echo "   Master Agent"
echo "      ↓ 发起连接到 Worker"
echo "   Worker Gateway (100.64.0.2:18789)"
echo "      │"
echo "   Worker Agent/Skills"
echo ""

echo "2. 通信方向:"
echo "   • Master → Worker: 主动发起 (通过 Tailscale)"
echo "   • Worker → Master: 不需要 (Worker 是被管理的)"
echo ""

echo "3. 技能执行位置:"
echo "   • 命令在 Worker 本地执行"
echo "   • 结果返回给 Master"
echo "   • Master 再返回给用户"
echo ""

ok "总结：Master 是大脑，Worker 是手脚！"
echo ""
