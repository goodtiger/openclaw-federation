#!/bin/bash
#
# 配置中心演示 - 展示 config-center.sh 的工作原理
#

TEST_DIR="/tmp/config-center-demo-$$"
mkdir -p "$TEST_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  配置中心 (config-center.sh) 工作原理演示                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
highlight() { echo -e "${CYAN}$1${NC}"; }

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "═══════════════════════════════════════════════════════════"
echo "【问题场景】没有配置中心会怎么样？"
echo "═══════════════════════════════════════════════════════════"
echo ""

highlight "场景：你有 3 台机器组成联邦"
echo ""
echo "  Master (VPS)         Worker1 (Mac)          Worker2 (Linux)"
echo "  ├─ Telegram Bot      ├─ Telegram Bot        ├─ Telegram Bot"
echo "  ├─ Model: GPT-4      ├─ Model: GPT-4        ├─ Model: GPT-4"
echo "  └─ Skill: docker     └─ Skill: apple-notes  └─ Skill: k8s"
echo ""

warn "问题 1：更新配置很麻烦"
echo ""
echo "  你想修改 Telegram 的 allowlist，需要在每台机器上修改配置！"
echo ""
echo "  Master:  vim ~/.openclaw/openclaw.json  ← 修改"
echo "  Worker1: vim ~/.openclaw/openclaw.json  ← 修改"
echo "  Worker2: vim ~/.openclaw/openclaw.json  ← 修改"
echo ""

warn "问题 2：配置不一致"
echo ""
echo "  Master:  allowFrom: [\"5145113446\"]"
echo "  Worker1: allowFrom: [\"5145113446\", \"1234567890\"]  ← 忘记同步"
echo "  Worker2: allowFrom: [\"5145113446\"]"
echo ""
echo "  导致：Worker1 可以接收其他人的消息，其他节点不行！"
echo ""

warn "问题 3：新增节点配置麻烦"
echo ""
echo "  新加入 Worker3，需要手动复制所有配置..."
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【解决方案】配置中心"
echo "═══════════════════════════════════════════════════════════"
echo ""

highlight "配置中心架构"
echo ""
echo "                    ┌─────────────┐"
echo "                    │   Master    │  ← 配置中心（唯一权威）"
echo "                    │  (Config    │"
echo "                    │   Center)   │"
echo "                    └──────┬──────┘"
echo "                           │"
echo "           ┌───────────────┼───────────────┐"
echo "           │ sync          │ sync          │ sync"
echo "           ▼               ▼               ▼"
echo "     ┌──────────┐   ┌──────────┐   ┌──────────┐"
echo "     │ Worker1  │   │ Worker2  │   │ Worker3  │"
echo "     │ (Sync)   │   │ (Sync)   │   │ (Sync)   │"
echo "     └──────────┘   └──────────┘   └──────────┘"
echo ""

info "Master 维护一份统一的配置"
info "所有 Worker 定期从 Master 同步"
info "配置变更只需修改 Master，自动推送到所有节点"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【演示】配置中心工作流程"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 创建模拟环境
mkdir -p "$TEST_DIR/master" "$TEST_DIR/worker1" "$TEST_DIR/worker2"

echo "【步骤 1】Master 创建统一配置"
echo "───────────────────────────────────────────────────────────"
echo ""

cat > "$TEST_DIR/master/config.json" << 'EOF'
{
  "version": 1,
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "8022xxxx:xxxxxxxx",
      "allowFrom": ["5145113446"],
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist"
    }
  },
  "models": {
    "primary": "openai/gpt-5.1-codex",
    "fallbacks": ["kimi-coding/k2p5"]
  },
  "agents": {
    "defaults": {
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4
    }
  },
  "federation": {
    "auto_sync": true,
    "sync_interval": 300
  }
}
EOF

success "Master 配置已创建"
info "配置包含："
echo "  - Telegram 通道设置"
echo "  - AI 模型配置"
echo "  - Agent 默认参数"
echo "  - 联邦同步设置"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "【步骤 2】Worker 节点首次同步"
echo "───────────────────────────────────────────────────────────"
echo ""

# Worker 1 本地配置（只有 Gateway）
cat > "$TEST_DIR/worker1/local.json" << 'EOF'
{
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.2",
    "auth": { "mode": "token", "token": "xxx" }
  }
}
EOF

info "Worker1 原始配置（仅 Gateway）:"
cat "$TEST_DIR/worker1/local.json" | jq .
echo ""

info "从 Master 拉取配置并合并..."
jq -s '.[0] * .[1]' "$TEST_DIR/worker1/local.json" "$TEST_DIR/master/config.json" > "$TEST_DIR/worker1/merged.json"

success "合并完成！"
echo ""
info "Worker1 最终配置:"
cat "$TEST_DIR/worker1/merged.json" | jq '{
  gateway: .gateway,
  channels: .channels,
  models: .models,
  agents: .agents
}'
echo ""

read -p "按 Enter 继续..."
echo ""

echo "【步骤 3】Master 更新配置"
echo "───────────────────────────────────────────────────────────"
echo ""

info "Master 添加新的 allowFrom 用户..."

# Master 更新配置
jq '.channels.telegram.allowFrom += ["1234567890"]' "$TEST_DIR/master/config.json" > "$TEST_DIR/master/config.json.new"
mv "$TEST_DIR/master/config.json.new" "$TEST_DIR/master/config.json"

success "Master 配置已更新"
info "新的 allowFrom: $(jq -r '.channels.telegram.allowFrom | join(", ")' "$TEST_DIR/master/config.json")"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "【步骤 4】Worker 自动同步更新"
echo "───────────────────────────────────────────────────────────"
echo ""

info "Worker1 检测到配置变更，自动同步..."

# Worker 重新拉取并合并
jq -s '.[0] * .[1]' "$TEST_DIR/worker1/local.json" "$TEST_DIR/master/config.json" > "$TEST_DIR/worker1/merged.json"

success "Worker1 配置已更新"
info "新的 allowFrom: $(jq -r '.channels.telegram.allowFrom | join(", ")' "$TEST_DIR/worker1/merged.json")"
echo ""

highlight "✓ 无需手动修改 Worker，配置自动同步！"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【实际使用】命令示例"
echo "═══════════════════════════════════════════════════════════"
echo ""

highlight "Master 节点（配置中心）:"
echo ""
echo "1. 启动配置服务:"
echo "   $ ./config-center.sh master start"
echo ""
echo "2. 修改配置（例如添加 Telegram 用户）:"
echo "   $ ./config-center.sh master update channels.telegram.allowFrom '[\"5145113446\", \"1234567890\"]'"
echo ""
echo "3. 查看当前配置:"
echo "   $ ./config-center.sh master export"
echo ""

highlight "Worker 节点:"
echo ""
echo "1. 手动同步配置:"
echo "   $ ./config-center.sh worker sync"
echo ""
echo "2. 启动自动同步（每5分钟自动检查）:"
echo "   $ ./config-center.sh worker daemon"
echo ""
echo "3. 查看与 Master 的配置差异:"
echo "   $ ./config-center.sh worker diff"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【总结】配置中心的价值"
echo "═══════════════════════════════════════════════════════════"
echo ""

success "1. 统一管理"
echo "   - 所有节点共享同一份配置"
echo "   - 修改一次，全集群生效"
echo ""

success "2. 自动同步"
echo "   - Worker 自动从 Master 拉取最新配置"
echo "   - 无需手动复制粘贴"
echo ""

success "3. 配置一致性"
echo "   - 避免人工操作导致的配置差异"
echo "   - 确保所有节点行为一致"
echo ""

success "4. 快速扩容"
echo "   - 新增节点自动同步配置"
echo "   - 无需手动配置每个节点"
echo ""

highlight "适用场景:"
echo "  ✓ 多��点联邦部署"
echo "  ✓ 需要统一调整配置（如 Telegram allowlist）"
echo "  ✓ 频繁修改配置的场景"
echo "  ✓ 大规模节点管理"
echo ""

highlight "不适用场景:"
echo "  ✗ 单节点部署（不需要同步）"
echo "  ✗ 各节点需要完全不同配置"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "演示完成！"
echo "═══════════════════════════════════════════════════════════"
echo ""
