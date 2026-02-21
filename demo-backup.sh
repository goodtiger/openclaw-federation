#!/bin/bash
#
# 备份功能演示
#

TEST_DIR="/tmp/backup-demo-$$"
mkdir -p "$TEST_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw 联邦部署 - 备份功能演示                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[DEMO]${NC} $1"; }
pass() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 模拟现有配置
echo "═══════════════════════════════════════════════════════════"
echo "【步骤 1】模拟已有 OpenClaw 配置"
echo "═══════════════════════════════════════════════════════════"
echo ""

mkdir -p "$TEST_DIR/root/.openclaw"

cat > "$TEST_DIR/root/.openclaw/openclaw.json" << 'EOF'
{
  "meta": { "version": "2026.2.19" },
  "gateway": {
    "port": 18789,
    "bind": "127.0.0.1",
    "auth": { "mode": "token", "token": "old-token" }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "8022xxxx:xxxxxxxx",
      "allowFrom": ["5145113446"],
      "important_setting": "我的重要配置"
    }
  },
  "models": {
    "primary": "gpt-4",
    "fallbacks": ["claude-3"]
  },
  "my_custom_config": {
    "theme": "dark",
    "language": "zh-CN",
    "notifications": true
  }
}
EOF

log "已创建模拟配置:"
cat "$TEST_DIR/root/.openclaw/openclaw.json" | jq '{
  gateway: .gateway.bind,
  channels: (.channels | keys),
  custom: .my_custom_config
}'
echo ""

read -p "按 Enter 继续..."
echo ""

# 执行备份
echo "═══════════════════════════════════════════════════════════"
echo "【步骤 2】部署脚本自动备份现有配置"
echo "═══════════════════════════════════════════════════════════"
echo ""

BACKUP_DIR="$TEST_DIR/root/.openclaw/.backups"
mkdir -p "$BACKUP_DIR"

BACKUP_NAME="openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
cp "$TEST_DIR/root/.openclaw/openclaw.json" "$BACKUP_DIR/$BACKUP_NAME"

pass "配置已自动备份！"
log "备份位置: $BACKUP_DIR/$BACKUP_NAME"
echo ""

# 显示备份内容
log "备份文件内容预览:"
head -20 "$BACKUP_DIR/$BACKUP_NAME"
echo "..."
echo ""

read -p "按 Enter 继续..."
echo ""

# 合并新配置
echo "═══════════════════════════════════════════════════════════"
echo "【步骤 3】合并新配置（保留原有设置）"
echo "═══════════════════════════════════════════════════════════"
echo ""

NEW_TOKEN="new-federation-token-$(openssl rand -hex 16)"

# 模拟配置合并
jq -s '.[0] * {
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.1",
    "auth": { "mode": "token", "token": "'$NEW_TOKEN'" },
    "tailscale": { "mode": "off" }
  },
  "meta": {
    "federationRole": "master",
    "backupFile": "'$BACKUP_NAME'",
    "mergedAt": "'$(date -Iseconds)'"
  }
}' "$TEST_DIR/root/.openclaw/openclaw.json" > "$TEST_DIR/root/.openclaw/openclaw.json.new"

mv "$TEST_DIR/root/.openclaw/openclaw.json.new" "$TEST_DIR/root/.openclaw/openclaw.json"

pass "配置已合并！"
echo ""

read -p "按 Enter 继续..."
echo ""

# 验证合并结果
echo "═══════════════════════════════════════════════════════════"
echo "【步骤 4】验证合并结果"
echo "═══════════════════════════════════════════════════════════"
echo ""

log "新配置内容:"
cat "$TEST_DIR/root/.openclaw/openclaw.json" | jq '{
  "新的 Gateway": .gateway,
  "保留的 Channels": .channels.telegram,
  "保留的 Models": .models,
  "保留的自定义配置": .my_custom_config,
  "元数据": .meta
}'

echo ""
pass "验证完成！"
echo ""

# 检查关键配置是否保留
if jq -e '.my_custom_config' "$TEST_DIR/root/.openclaw/openclaw.json" > /dev/null 2>&1; then
  pass "✓ 自定义配置已保留"
fi

if jq -e '.channels.telegram.important_setting' "$TEST_DIR/root/.openclaw/openclaw.json" > /dev/null 2>&1; then
  pass "✓ Telegram 配置已保留"
fi

if [[ "$(jq -r '.gateway.bind' "$TEST_DIR/root/.openclaw/openclaw.json")" == "100.64.0.1" ]]; then
  pass "✓ Gateway 已更新为联邦配置"
fi

echo ""

read -p "按 Enter 继续..."
echo ""

# 恢复演示
echo "═══════════════════════════════════════════════════════════"
echo "【步骤 5】如何从备份恢复（如果需要）"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "如果部署后需要恢复原有配置:"
echo ""
echo "方法 1: 直接恢复备份"
echo "  cp $BACKUP_DIR/$BACKUP_NAME $TEST_DIR/root/.openclaw/openclaw.json"
echo ""
echo "方法 2: 使用配置管理工具"
echo "  ./config-manager.sh restore-latest"
echo ""
echo "方法 3: 查看备份列表"
echo "  ls -la $BACKUP_DIR/"
echo ""

pass "备份和恢复演示完成！"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "总结"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "✅ 脚本会自动备份现有配置"
echo "✅ 备份保存在: ~/.openclaw/.backups/"
echo "✅ 配置合并时会保留原有设置"
echo "✅ 随时可以恢复备份"
echo ""
echo "部署命令:"
echo "  sudo ./deploy-federation.sh master"
echo ""
echo "备份位置:"
echo "  ~/.openclaw/.backups/openclaw.json.backup.YYYYMMDD_HHMMSS"
echo ""
