#!/bin/bash
#
# Gateway 配置位置说明
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Gateway 配置位置详解                                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
highlight() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
log() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo "═══════════════════════════════════════════════════════════"
echo "【位置 1】配置文件 ~/.openclaw/openclaw.json"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "这是 Gateway 配置的存储位置："
echo ""
echo "文件: ~/.openclaw/openclaw.json"
echo ""
echo "内容示例:"
cat << 'EOF'
{
  "gateway": {
    "port": 18789,                          ← 监听端口
    "bind": "0.0.0.0",                      ← 绑定地址
    "mode": "local",                         ← 运行模式
    "auth": {
      "mode": "token",                       ← 认证方式
      "token": "your-token-here"             ← 访问令牌
    },
    "tailscale": {
      "mode": "off",                         ← Tailscale 集成
      "resetOnExit": false
    }
  }
}
EOF

echo ""
warn "⚠️ 重要: 不要手动编辑这个文件！"
echo "   使用 deploy-federation.sh 脚本来修改配置"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【位置 2】部署脚本中的配置逻辑"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "配置是在 deploy-federation.sh 脚本中生成的："
echo ""

echo "1. 默认配置（脚本中的常量）:"
echo "   GATEWAY_PORT=18789"
echo ""

echo "2. 绑定地址（根据参数决定）:"
echo "   ├─ 默认: bind=\"0.0.0.0\"           (所有接口)"
echo "   └─ 可选: bind=\"100.64.0.x\"        (Tailscale IP，使用 --bind-tailscale)"
echo ""

echo "3. Token（自动生成或从文件读取）:"
echo "   ├─ Master: 生成新 Token"
echo "   └─ Worker: 从 --token 参数或文件读取"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【位置 3】配置生成的具体代码"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "在 deploy-federation.sh 脚本中，configure_gateway_safe() 函数负责配置："
echo ""

echo "函数调用链:"
echo ""
echo "main()"
echo "  └── configure_gateway_safe()"
echo "       ├── backup_config()          ← 备份现有配置"
echo "       ├── merge_config_with_jq()   ← 合并配置（如果有现有配置）"
echo "       └── create_basic_config()    ← 创建新配置（如果是新安装）"
echo ""

highlight "配置生成的核心代码:"
echo ""
cat << 'EOF'
# 安全合并配置（保留原有设置）
merge_config_with_jq() {
  local gateway_config='{
    "gateway": {
      "port": 18789,
      "bind": "$ip",              ← 这里设置绑定地址
      "auth": {
        "mode": "token",
        "token": "$TOKEN"          ← 这里设置 Token
      }
    }
  }'
  
  # 合并到现有配置
  jq -s '.[0] * .[1]' "$CONFIG_FILE" <<< "$gateway_config"
}
EOF

echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【总结】Gateway 配置的三个层级"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "┌─────────────────────────────────────────────────────────┐"
echo "│  层级 1: 脚本常量 (代码中硬编码)                         │"
echo "│  ├─ 端口: 18789                                         │"
echo "│  └─ 认证模式: token                                     │"
echo "├─────────────────────────────────────────────────────────┤"
echo "│  层级 2: 运行时参数 (命令行传入)                         │"
echo "│  ├─ bind: 0.0.0.0 或 100.64.0.x (由 --bind-tailscale 决定)│"
echo "│  ├─ token: 从参数或文件读取                              │"
echo "│  └─ role: master 或 worker                              │"
echo "├─────────────────────────────────────────────────────────┤"
echo "│  层级 3: 配置文件 (~/.openclaw/openclaw.json)           │"
echo "│  └─ 最终生成的配置，OpenClaw 读取使用                    │"
echo "└─────────────────────────────────────────────────────────┘"

echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【修改 Gateway 配置的方法】"
echo "═══════════════════════════════════════════════════════════"
echo ""

info "方法 1: 重新运行部署脚本（推荐）"
echo ""
echo "  # 修改绑定地址"
echo "  sudo ./deploy-federation.sh master --bind-tailscale"
echo ""
echo "  # 这会："
echo "  # 1. 备份现有配置"
echo "  # 2. 更新 gateway.bind"
echo "  # 3. 保留其他所有配置"
echo ""

info "方法 2: 使用 OpenClaw 命令（部分配置）"
echo ""
echo "  # 重启 Gateway"
echo "  openclaw gateway restart"
echo ""
echo "  # 查看 Gateway 状态"
echo "  openclaw gateway status"
echo ""

info "方法 3: 手动编辑（不推荐，除非你知道在做什么）"
echo ""
echo "  # 先备份"
echo "  cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.manual-backup"
echo ""
echo "  # 编辑（风险自负）"
echo "  nano ~/.openclaw/openclaw.json"
echo ""
echo "  # 重启生效"
echo "  openclaw gateway restart"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【常见配置修改场景】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "场景 1: 修改绑定地址"
echo "───────────────────────────────────────────────────────────"
echo "  当前: bind: \"0.0.0.0\""
echo "  目标: bind: \"100.64.0.1\" (Tailscale IP)"
echo ""
echo "  命令: sudo ./deploy-federation.sh master --bind-tailscale"
echo ""

echo "场景 2: 更换 Token"
echo "───────────────────────────────────────────────────────────"
echo "  1. 删除旧 Token 文件: rm ~/.openclaw/.federation-token"
echo "  2. 重新部署: sudo ./deploy-federation.sh master"
echo "  3. 将新 Token 复制到所有 Worker"
echo ""

echo "场景 3: 修改端口"
echo "───────────────────────────────────────────────────────────"
echo "  警告: 不建议修改端口！"
echo "  如果必须修改，编辑脚本中的 GATEWAY_PORT 常量"
echo "  然后重新运行部署脚本"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【查看当前 Gateway 配置】"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "命令:"
echo "  jq '.gateway' ~/.openclaw/openclaw.json"
echo ""

echo "输出示例:"
cat << 'EOF'
{
  "port": 18789,
  "bind": "100.64.0.1",
  "mode": "local",
  "auth": {
    "mode": "token",
    "token": "a7ec2f47..."
  }
}
EOF

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "总结"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "✅ Gateway 配置位置: ~/.openclaw/openclaw.json"
echo "✅ 配置生成位置: deploy-federation.sh 脚本"
echo "✅ 推荐修改方式: 重新运行部署脚本"
echo "✅ 安全机制: 自动备份 + 配置合并"
echo ""
