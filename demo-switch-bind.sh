#!/bin/bash
#
# 绑定模式切换演示
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Worker 节点绑定模式切换演示                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
ok() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }

echo "═══════════════════════════════════════════════════════════"
echo "【场景】Worker 节点部署后需要本地调试"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "步骤 1: Worker 正常部署（绑定 Tailscale IP）"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  $ sudo ./deploy-federation.sh worker \\"
echo "      --master-ip 100.64.0.1 \\"
echo "      --token \"xxx\" \\"
echo "      --bind-tailscale"
echo ""
ok "  ✓ Worker 部署完成"
ok "  ✓ 绑定: 100.64.0.2:18789 (Tailscale IP)"
ok "  ✓ Master 可以管理 Worker"
echo ""

warn "  ⚠️  问题: 无法在本地使用 127.0.0.1 调试!"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【解决】使用 switch-bind-mode.sh 切换到 0.0.0.0"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "步骤 2: 切换到开放模式 (0.0.0.0)"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  $ ./switch-bind-mode.sh to-all"
echo ""
echo "  === 切换到开放模式 (0.0.0.0) ==="
echo ""
echo "  [OK] 配置已备份: openclaw.json.backup.20260221_151234"
echo "  [OK] 绑定地址已更新: 100.64.0.2 → 0.0.0.0"
echo ""
echo "  是否立即重启 Gateway 生效? [Y/n]: Y"
echo "  [INFO] 重启 Gateway..."
echo "  [OK] Gateway 重启成功"
echo ""
ok "  ✓ 切换完成！"
echo ""

info "现在 Worker 支持:"
ok "  ✅ curl http://127.0.0.1:18789/health  (本地)"
ok "  ✅ curl http://192.168.1.10:18789/health (内网)"
ok "  ✅ curl http://100.64.0.2:18789/health  (Tailscale)"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【完成调试】切换回安全模式"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "步骤 3: 调试完成后，切回安全模式"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  $ ./switch-bind-mode.sh to-tailscale"
echo ""
echo "  === 切换到安全模式 (Tailscale IP) ==="
echo ""
echo "  [OK] 配置已备份: openclaw.json.backup.20260221_152345"
echo "  [OK] 绑定地址已更新: 0.0.0.0 → 100.64.0.2"
echo ""
echo "  是否立即重启 Gateway 生效? [Y/n]: Y"
echo "  [INFO] 重启 Gateway..."
echo "  [OK] Gateway 重启成功"
echo ""
ok "  ✓ 切换完成！"
echo ""

info "现在 Worker:"
ok "  ✅ 仅可通过 Tailscale 访问（安全）"
ok "  ✅ Master 仍可正常管理"
no() { echo -e "\033[0;31m$1\033[0m"; }
no "  ❌ 无法通过 127.0.0.1 访问"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【其他功能】查看状态和测试连接"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "查看当前状态:"
echo "  $ ./switch-bind-mode.sh status"
echo ""
echo "  === 当前 Gateway 配置 ==="
echo ""
echo "    绑定地址: 100.64.0.2"
echo "    端口: 18789"
echo ""
echo "  当前模式: 安全模式 (Tailscale IP)"
echo "    ✅ 仅可通过 Tailscale 网络访问"
echo "    ✅ 天然安全，无需防火墙"
echo ""

echo ""
info "测试连接:"
echo "  $ ./switch-bind-mode.sh test"
echo ""
echo "  === 测试连接 ==="
echo ""
echo "  ✅ Tailscale (100.64.0.2:18789) 可访问"
echo ""

echo ""
info "回滚配置:"
echo "  $ ./switch-bind-mode.sh rollback"
echo ""
echo "  可用的备份:"
echo "    1. openclaw.json.backup.20260221_152345"
echo "    2. openclaw.json.backup.20260221_151234"
echo ""
echo "  选择要恢复的备份 [1-2]: 2"
echo "  [OK] 当前配置已备份"
echo "  [OK] 已恢复到: openclaw.json.backup.20260221_151234"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【完整命令参考】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "查看状态:"
echo "  ./switch-bind-mode.sh status"
echo ""

echo "切换到 0.0.0.0（开放模式）:"
echo "  ./switch-bind-mode.sh to-all"
echo ""

echo "切换到 Tailscale IP（安全模式）:"
echo "  ./switch-bind-mode.sh to-tailscale"
echo ""

echo "测试连接:"
echo "  ./switch-bind-mode.sh test"
echo ""

echo "回滚配置:"
echo "  ./switch-bind-mode.sh rollback"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【总结】"
echo "═══════════════════════════════════════════════════════════"
echo ""
ok "Worker 部署后可以灵活切换绑定模式:"
echo ""
echo "  1. 部署时绑定 Tailscale IP（安全）"
echo "  2. 需要调试时 → 切换到 0.0.0.0"
echo "  3. 调试完成后 → 切回 Tailscale IP"
echo "  4. 随时回滚到之前的配置"
echo ""
echo "这样既有安全性，又有灵活性！"
echo ""
