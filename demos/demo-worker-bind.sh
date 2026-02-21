#!/bin/bash
#
# Worker 节点 Gateway 绑定 IP 影响分析
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Worker 节点 Gateway 绑定 IP 详解                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
ok() { echo -e "${GREEN}$1${NC}"; }
no() { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }

echo "═══════════════════════════════════════════════════════════"
echo "【关键问题】Worker 绑定 Tailscale IP 后能否本地访问？"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "答案是：不能！"
echo ""

echo "绑定 Tailscale IP (100.64.0.x) 后："
echo ""
no "  ❌ http://127.0.0.1:18789    (localhost) - 无法访问"
no "  ❌ http://192.168.1.10:18789 (内网 IP)   - 无法访问"
no "  ❌ http://公网IP:18789       (公网)     - 无法访问"
ok "  ✅ http://100.64.0.5:18789   (Tailscale) - 可以访问"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【对比】两种绑定方式"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "方式 1: 默认绑定 0.0.0.0"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "配置:"
echo '  { "gateway": { "bind": "0.0.0.0", "port": 18789 } }'
echo ""
echo "访问方式:"
ok "  ✅ curl http://127.0.0.1:18789/health      (本机)"
ok "  ✅ curl http://192.168.1.10:18789/health   (内网)"
ok "  ✅ curl http://100.64.0.5:18789/health     (Tailscale)"
ok "  ✅ curl http://公网IP:18789/health         (公网，如果防火墙允许)"
echo ""
warn "  安全性：较低（所有接口都可访问）"
echo ""

echo "方式 2: 绑定 Tailscale IP (--bind-tailscale)"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "配置:"
echo '  { "gateway": { "bind": "100.64.0.5", "port": 18789 } }'
echo ""
echo "访问方式:"
no "  ❌ curl http://127.0.0.1:18789/health      (本机)"
no "  ❌ curl http://192.168.1.10:18789/health   (内网)"
ok "  ✅ curl http://100.64.0.5:18789/health     (Tailscale)"
no "  ❌ curl http://公网IP:18789/health         (公网)"
echo ""
ok "  安全性：高（仅 Tailscale 网络可访问）"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【Worker 节点的实际情况】"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "Worker 节点的 Gateway 主要用于："
echo ""
echo "  1. 接受 Master 的管理命令"
echo "     Master ──Tailscale──► Worker Gateway"
echo ""
echo "  2. 提供健康检查接口"
echo "     Master ──Tailscape──► Worker /health"
echo ""
echo "  3. 在 Worker 上执行命令"
echo "     Master ──Tailscale──► Worker ──► 本地执行"
echo ""

warn "Worker 通常不需要本地直接访问自己的 Gateway！"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【影响分析】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "绑定 Tailscale IP 的影响："
echo ""

echo "✅ 正面影响："
echo "  • 更安全（仅 Tailscale 可访问）"
echo "  • 无需防火墙配置"
echo "  • 强制加密通信"
echo ""

echo "⚠️  负面影响："
echo "  • 本地调试不便（不能用 127.0.0.1）"
echo "  • 内网其他机器无法直接访问"
echo "  • 如果 Tailscale 未启动，Gateway 完全不可访问"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【解决方案】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "方案 1: Worker 保持默认绑定（推荐）"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # Worker 使用默认绑定 0.0.0.0"
echo "  sudo ./deploy-federation.sh worker \\"
echo "    --master-ip 100.64.0.1 \\"
echo "    --token \"xxx\""
echo ""
info "  优点："
echo "  • 本地可以访问（127.0.0.1）"
echo "  • 内网可以访问（192.168.x.x）"
echo "  • Tailscale 也可以访问"
echo ""
warn "  缺点："
echo "  • 需要配置防火墙保护"
echo "  • 可能暴露在内网"
echo ""

echo "方案 2: Master 绑定 Tailscale，Worker 绑定 0.0.0.0"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # Master（安全模式）"
echo "  sudo ./deploy-federation.sh master --bind-tailscale"
echo ""
echo "  # Worker（默认模式，方便本地管理）"
echo "  sudo ./deploy-federation.sh worker \\"
echo "    --master-ip 100.64.0.1 \\"
echo "    --token \"xxx\""
echo ""
info "  这是最灵活的组合！"
echo ""

echo "方案 3: 所有节点都绑定 Tailscale（最安全）"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # 所有节点都使用 --bind-tailscale"
echo ""
info "  适合："
echo "  • 生产环境"
echo "  • 高安全要求场景"
echo "  • 不需要本地调试"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【本地调试 Worker 的方法】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "如果 Worker 绑定了 Tailscale IP，如何本地调试？"
echo ""

echo "方法 1: 使用 Tailscale IP 访问"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # 即使在本机，也使用 Tailscale IP"
echo "  curl http://100.64.0.5:18789/health"
echo ""

echo "方法 2: 临时切换到 0.0.0.0"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # 停止 Gateway"
echo "  openclaw gateway stop"
echo ""
echo "  # 修改配置 bind 为 0.0.0.0"
echo "  jq '.gateway.bind = \"0.0.0.0\"' ~/.openclaw/openclaw.json > /tmp/config.json"
echo "  mv /tmp/config.json ~/.openclaw/openclaw.json"
echo ""
echo "  # 启动 Gateway"
echo "  openclaw gateway start"
echo ""
echo "  # 现在可以用 127.0.0.1 访问了"
echo "  curl http://127.0.0.1:18789/health"
echo ""

echo "方法 3: 使用 SSH 隧道"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  # 在本地创建隧道"
echo "  ssh -L 18789:100.64.0.5:18789 user@worker-node"
echo ""
echo "  # 然后访问本地端口"
echo "  curl http://127.0.0.1:18789/health"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【总结】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "问题：Worker 绑定 Tailscale IP 后能否本地访问？"
echo ""
no "答案：不能直接访问 127.0.0.1 或内网 IP"
echo ""

echo "但是："
ok "  ✅ 可以通过 Tailscale IP 访问（包括本机）"
ok "  ✅ Master 可以正常管理 Worker"
ok "  ✅ 安全性更高"
echo ""

echo "推荐做法："
echo ""
echo "  Master: 绑定 Tailscale IP（--bind-tailscale）"
echo "  Worker:  默认绑定 0.0.0.0（方便本地管理）"
echo ""
info "这样既有安全性，又保留了灵活性！"
echo ""
