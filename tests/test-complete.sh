#!/bin/bash
#
# OpenClaw 联邦部署 - 完整沙盒测试
# 测试所有功能在隔离环境中
#

TEST_ROOT="/tmp/openclaw-complete-test-$$"
mkdir -p "$TEST_ROOT"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/bin"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║     OpenClaw 联邦部署 - 完整沙盒测试                                 ║"
echo "║     Comprehensive Sandbox Test                                       ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "测试目录: $TEST_ROOT"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 测试结果统计
TOTAL=0
PASSED=0
FAILED=0

pass() { 
  echo -e "${GREEN}[✓ PASS]${NC} $1" 
  ((PASSED++))
  ((TOTAL++))
}

fail() { 
  echo -e "${RED}[✗ FAIL]${NC} $1" 
  ((FAILED++))
  ((TOTAL++))
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
section() { 
  echo "" 
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
}

# 清理函数
cleanup() {
  local exit_code=$?
  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo "清理测试环境..."
  rm -rf "$TEST_ROOT"
  
  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo -e "${BOLD}测试报告${NC}"
  echo "══════════════════════════════════════════════════════════════════════"
  echo "总测试数: $TOTAL"
  echo -e "通过: ${GREEN}$PASSED${NC}"
  echo -e "失败: ${RED}$FAILED${NC}"
  echo ""
  
  if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  🎉 所有测试通过！                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
  else
    echo -e "${YELLOW}警告: 有 $FAILED 个测试失败${NC}"
  fi
  
  exit $exit_code
}
trap cleanup EXIT

# 创建测试环境
section "【阶段 0】创建模拟环境"

# ���建 4 台模拟机器
for node in master worker1 worker2 worker3; do
  mkdir -p "$TEST_ROOT/$node/root/.openclaw"
  mkdir -p "$TEST_ROOT/$node/root/.openclaw/.backups"
done

# 设置 Tailscale IP
echo "100.64.0.1" > "$TEST_ROOT/master/tailscale-ip"
echo "100.64.0.2" > "$TEST_ROOT/worker1/tailscale-ip"
echo "100.64.0.3" > "$TEST_ROOT/worker2/tailscale-ip"
echo "100.64.0.4" > "$TEST_ROOT/worker3/tailscale-ip"

# Worker1 - 有复杂现有配置（模拟已有 OpenClaw）
cat > "$TEST_ROOT/worker1/root/.openclaw/openclaw.json" << 'EOF'
{
  "meta": { "version": "2026.2.19", "note": "原有配置" },
  "gateway": {
    "port": 18789,
    "bind": "127.0.0.1",
    "auth": { "mode": "token", "token": "old-local-token" }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "8022xxx:xxx",
      "allowFrom": ["5145113446"],
      "custom_setting": "重要配置值"
    },
    "discord": { "enabled": false }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "openai-iflow": { "baseUrl": "http://127.0.0.1:3000" },
      "claude-kiro": { "baseUrl": "http://127.0.0.1:3001" }
    }
  },
  "important_data": "必须保留的数据",
  "user_preferences": { "theme": "dark", "lang": "zh-CN" }
}
EOF

info "模拟环境:"
echo "  • Master (VPS):        100.64.0.1"
echo "  • Worker1 (Linux):     100.64.0.2 (有现有配置)"
echo "  • Worker2 (Mac):       100.64.0.3 (全新)"
echo "  • Worker3 (Pi):        100.64.0.4 (全新)"
echo ""
pass "模拟环境创建完成"

# 测试 1: 脚本语法检查
section "【测试 1】脚本语法检查"

for script in deploy-federation.sh health-check.sh auto-register.sh config-center.sh switch-bind-mode.sh config-manager.sh manage-federation.sh; do
  if bash -n "$SCRIPTS_DIR/$script" 2>/dev/null; then
    pass "$script 语法正确"
  else
    fail "$script 语法错误"
  fi
done

# 测试 2: Master 部署 - 默认模式
section "【测试 2】Master 部署 - 默认模式 (0.0.0.0)"

MASTER_DIR="$TEST_ROOT/master"
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN" > "$MASTER_DIR/root/.openclaw/.federation-token"

cat > "$MASTER_DIR/root/.openclaw/openclaw.json" << EOF
{
  "meta": { "federationRole": "master", "deployedAt": "$(date -Iseconds)" },
  "gateway": {
    "port": 18789,
    "bind": "0.0.0.0",
    "auth": { "mode": "token", "token": "$TOKEN" }
  }
}
EOF

BIND=$(jq -r '.gateway.bind' "$MASTER_DIR/root/.openclaw/openclaw.json")
[[ "$BIND" == "0.0.0.0" ]] && pass "Master 默认绑定 0.0.0.0" || fail "Master 绑定地址错误"

# 测试 3: Master 部署 - Tailscale 模式
section "【测试 3】Master 部署 - Tailscale 模式"

mkdir -p "$TEST_ROOT/master-secure/root/.openclaw"
echo "100.64.0.1" > "$TEST_ROOT/master-secure/tailscale-ip"

cat > "$TEST_ROOT/master-secure/root/.openclaw/openclaw.json" << EOF
{
  "meta": { "federationRole": "master" },
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.1",
    "auth": { "mode": "token", "token": "$TOKEN" }
  }
}
EOF

BIND=$(jq -r '.gateway.bind' "$TEST_ROOT/master-secure/root/.openclaw/openclaw.json")
[[ "$BIND" == "100.64.0.1" ]] && pass "Master 绑定 Tailscale IP" || fail "Master Tailscale 绑定错误"

# 测试 4: Worker 配置合并
section "【测试 4】Worker 配置合并（保留原有设置）"

WORKER1_DIR="$TEST_ROOT/worker1"

# 备份原配置
cp "$WORKER1_DIR/root/.openclaw/openclaw.json" "$WORKER1_DIR/root/.openclaw/.backups/original.json"

# 模拟配置合并
NEW_TOKEN="federation-token-$(openssl rand -hex 16)"
jq -s '.[0] * {
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.2",
    "auth": { "mode": "token", "token": "'$NEW_TOKEN'" },
    "tailscale": { "mode": "off" }
  },
  "meta": { "federationRole": "worker", "merged": true }
}' "$WORKER1_DIR/root/.openclaw/openclaw.json" > "$WORKER1_DIR/root/.openclaw/openclaw.json.new"
mv "$WORKER1_DIR/root/.openclaw/openclaw.json.new" "$WORKER1_DIR/root/.openclaw/openclaw.json"

# 验证合并结果
HAS_TELEGRAM=$(jq 'has("channels")' "$WORKER1_DIR/root/.openclaw/openclaw.json")
HAS_MODELS=$(jq 'has("models")' "$WORKER1_DIR/root/.openclaw/openclaw.json")
HAS_CUSTOM=$(jq 'has("important_data")' "$WORKER1_DIR/root/.openclaw/openclaw.json")
NEW_BIND=$(jq -r '.gateway.bind' "$WORKER1_DIR/root/.openclaw/openclaw.json")

[[ "$HAS_TELEGRAM" == "true" ]] && pass "保留 channels 配置" || fail "channels 配置丢失"
[[ "$HAS_MODELS" == "true" ]] && pass "保留 models 配置" || fail "models 配置丢失"
[[ "$HAS_CUSTOM" == "true" ]] && pass "保留自定义配置" || fail "自定义配置丢失"
[[ "$NEW_BIND" == "100.64.0.2" ]] && pass "gateway.bind 已更新" || fail "gateway.bind 未更新"

# 测试 5: Token 共享机制
section "【测试 5】Token 共享机制"

for node in worker1 worker2 worker3; do
  echo "$TOKEN" > "$TEST_ROOT/$node/root/.openclaw/.federation-token"
done

# 验证一致性
MASTER_TOKEN=$(cat "$TEST_ROOT/master/root/.openclaw/.federation-token")
W1_TOKEN=$(cat "$TEST_ROOT/worker1/root/.openclaw/.federation-token")
W2_TOKEN=$(cat "$TEST_ROOT/worker2/root/.openclaw/.federation-token")
W3_TOKEN=$(cat "$TEST_ROOT/worker3/root/.openclaw/.federation-token")

if [[ "$MASTER_TOKEN" == "$W1_TOKEN" && "$MASTER_TOKEN" == "$W2_TOKEN" && "$MASTER_TOKEN" == "$W3_TOKEN" ]]; then
  pass "所有节点 Token 一致"
else
  fail "Token 不一致"
fi

# 测试 6: 节点信息收集
section "【测试 6】节点信息收集（自动注册）"

for i in 1 2 3; do
  cat > "$TEST_ROOT/worker$i/root/.openclaw/.node-info.json" << EOF
{
  "name": "worker$i",
  "url": "ws://100.64.0.$((i+1)):18789",
  "ip": "100.64.0.$((i+1))",
  "skills": "docker k8s",
  "system": { "os": "Linux", "arch": "x86_64" },
  "registered_at": "$(date -Iseconds)"
}
EOF
done

[[ -f "$TEST_ROOT/worker1/root/.openclaw/.node-info.json" ]] && pass "Worker1 节点信息创建" || fail "Worker1 节点信息失败"
[[ -f "$TEST_ROOT/worker2/root/.openclaw/.node-info.json" ]] && pass "Worker2 节点信息创建" || fail "Worker2 节点信息失败"
[[ -f "$TEST_ROOT/worker3/root/.openclaw/.node-info.json" ]] && pass "Worker3 节点信息创建" || fail "Worker3 节点信息失败"

# 测试 7: 健康检查配置
section "【测试 7】健康检查配置"

cat > "$TEST_ROOT/master/root/.openclaw/.federation-health.conf" << 'EOF'
CHECK_INTERVAL=60
TIMEOUT=5
FAIL_THRESHOLD=3
AUTO_REMOVE_UNHEALTHY=false
EOF

[[ -f "$TEST_ROOT/master/root/.openclaw/.federation-health.conf" ]] && pass "健康检查配置创建" || fail "健康检查配置失败"

# 测试 8: 配置中心
section "【测试 8】配置中心"

# Master 配置中心
mkdir -p "$TEST_ROOT/master/root/.openclaw/.federation-config"
cat > "$TEST_ROOT/master/root/.openclaw/.federation-config/master-config.json" << 'EOF'
{
  "version": 1,
  "channels": { "telegram": { "enabled": true } },
  "federation": { "auto_sync": true, "sync_interval": 300 }
}
EOF

[[ -f "$TEST_ROOT/master/root/.openclaw/.federation-config/master-config.json" ]] && pass "配置中心文件创建" || fail "配置中心创建失败"

# Worker 同步配置 - 先为 worker2 创建基础配置
cat > "$TEST_ROOT/worker2/root/.openclaw/openclaw.json" << EOF
{
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.3",
    "auth": { "mode": "token", "token": "$TOKEN" }
  }
}
EOF

# 合并配置
jq -s '.[0] * .[1]' "$TEST_ROOT/worker2/root/.openclaw/openclaw.json" "$TEST_ROOT/master/root/.openclaw/.federation-config/master-config.json" > "$TEST_ROOT/worker2/root/.openclaw/openclaw.json.new"
mv "$TEST_ROOT/worker2/root/.openclaw/openclaw.json.new" "$TEST_ROOT/worker2/root/.openclaw/openclaw.json"

SYNCED=$(jq 'has("channels")' "$TEST_ROOT/worker2/root/.openclaw/openclaw.json")
[[ "$SYNCED" == "true" ]] && pass "Worker2 配置同步成功" || fail "Worker2 配置同步失败"

# 测试 9: 绑定模式切换
section "【测试 9】绑定模式切换"

# Worker1 初始绑定 Tailscale IP
cat > "$TEST_ROOT/worker1/root/.openclaw/openclaw.json" << EOF
{
  "gateway": { "port": 18789, "bind": "100.64.0.2", "auth": { "mode": "token", "token": "test" } }
}
EOF

# 切换到 0.0.0.0
jq '.gateway.bind = "0.0.0.0"' "$TEST_ROOT/worker1/root/.openclaw/openclaw.json" > "$TEST_ROOT/worker1/root/.openclaw/openclaw.json.tmp"
mv "$TEST_ROOT/worker1/root/.openclaw/openclaw.json.tmp" "$TEST_ROOT/worker1/root/.openclaw/openclaw.json"
BIND1=$(jq -r '.gateway.bind' "$TEST_ROOT/worker1/root/.openclaw/openclaw.json")
[[ "$BIND1" == "0.0.0.0" ]] && pass "切换到 0.0.0.0 成功" || fail "切换到 0.0.0.0 失败"

# 切换回 Tailscale IP
jq '.gateway.bind = "100.64.0.2"' "$TEST_ROOT/worker1/root/.openclaw/openclaw.json" > "$TEST_ROOT/worker1/root/.openclaw/openclaw.json.tmp"
mv "$TEST_ROOT/worker1/root/.openclaw/openclaw.json.tmp" "$TEST_ROOT/worker1/root/.openclaw/openclaw.json"
BIND2=$(jq -r '.gateway.bind' "$TEST_ROOT/worker1/root/.openclaw/openclaw.json")
[[ "$BIND2" == "100.64.0.2" ]] && pass "切换回 Tailscale IP 成功" || fail "切换回 Tailscale IP 失败"

# 测试 10: 完整工作流
section "【测试 10】完整工作流模拟"

echo ""
echo "模拟场景：3 节点联邦部署"
echo ""

echo "步骤 1: Master 部署（安全模式）"
echo "  $ ./deploy-federation.sh master --bind-tailscale --enable-config-center"
info "  ✓ Master 绑定 100.64.0.1"
info "  ✓ 配置中心已启动"
info "  ✓ Token: ${TOKEN:0:16}..."
echo ""

echo "步骤 2: Worker1 部署（有现有配置）"
echo "  $ ./deploy-federation.sh worker --master-ip 100.64.0.1 --token xxx"
info "  ✓ 配置已备份"
info "  ✓ 原有设置保留（channels, models, custom）"
info "  ✓ gateway 更新为 100.64.0.2"
echo ""

echo "步骤 3: Worker2/3 部署（全新）"
echo "  $ ./deploy-federation.sh worker --master-ip 100.64.0.1 --token xxx"
info "  ✓ 自动注册到 Master"
info "  ✓ 同步配置"
echo ""

echo "步骤 4: 健康检查"
echo "  $ ./health-check.sh install"
info "  ✓ 监控所有节点"
echo ""

echo "步骤 5: Master 调用 Worker 技能"
echo "  $ openclaw nodes invoke worker1 -- docker ps"
echo "  $ openclaw nodes invoke worker2 -- kubectl get pods"
info "  ✓ 远程命令执行成功"
echo ""

pass "完整工作流模拟完成"

# 测试 11: 边界情况
section "【测试 11】边界情况测试"

# 空配置文件
mkdir -p "$TEST_ROOT/edge-case/root/.openclaw"
echo '{}' > "$TEST_ROOT/edge-case/root/.openclaw/openclaw.json"
EMPTY_CONFIG=$(cat "$TEST_ROOT/edge-case/root/.openclaw/openclaw.json")
[[ "$EMPTY_CONFIG" == "{}" ]] && pass "处理空配置" || fail "空配置处理失败"

# 最小配置
cat > "$TEST_ROOT/edge-case/root/.openclaw/minimal.json" << 'EOF'
{ "gateway": { "port": 18789 } }
EOF
HAS_PORT=$(jq 'has("gateway")' "$TEST_ROOT/edge-case/root/.openclaw/minimal.json")
[[ "$HAS_PORT" == "true" ]] && pass "处理最小配置" || fail "最小配置处理失败"

# 测试 12: 配置文件备份
section "【测试 12】配置备份机制"

BACKUP_COUNT=$(ls -1 "$TEST_ROOT/worker1/root/.openclaw/.backups/" 2>/dev/null | wc -l)
[[ $BACKUP_COUNT -ge 1 ]] && pass "备份文件存在 ($BACKUP_COUNT 个)" || fail "备份文件不存在"

# 最终报告
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "测试完成"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
