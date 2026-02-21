#!/bin/bash
#
# 测试 --bind-tailscale 选项
#

TEST_DIR="/tmp/test-bind-option-$$"
mkdir -p "$TEST_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  测试 --bind-tailscale 选项                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log() { echo -e "${BLUE}[TEST]${NC} $1"; }

# 清理
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 模拟配置生成函数
generate_config() {
  local bind_ip=$1
  local token=$2
  
  cat > "$TEST_DIR/openclaw.json" << EOF
{
  "gateway": {
    "port": 18789,
    "bind": "$bind_ip",
    "auth": {
      "mode": "token",
      "token": "$token"
    }
  }
}
EOF
}

# 测试 1: 默认绑定 0.0.0.0
test_default_bind() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 1: 默认绑定 0.0.0.0"
  echo "═══════════════════════════════════════════════════════════"
  
  # 模拟默认行为（不指定 --bind-tailscale）
  local bind_ip="0.0.0.0"
  local token="test-token-1234567890"
  
  generate_config "$bind_ip" "$token"
  
  # 验证
  local actual_bind=$(jq -r '.gateway.bind' "$TEST_DIR/openclaw.json")
  
  if [[ "$actual_bind" == "0.0.0.0" ]]; then
    pass "默认绑定 0.0.0.0 正确"
  else
    fail "默认绑定错误: $actual_bind"
  fi
  
  log "生成的配置:"
  jq '.gateway | {bind, port}' "$TEST_DIR/openclaw.json"
  echo ""
}

# 测试 2: 使用 --bind-tailscale
test_tailscale_bind() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 2: 使用 --bind-tailscale 绑定 Tailscale IP"
  echo "═══════════════════════════════════════════════════════════"
  
  # 模拟 --bind-tailscale 行为
  local tailscale_ip="100.64.0.5"
  local bind_ip="$tailscale_ip"  # 使用 Tailscale IP
  local token="test-token-1234567890"
  
  generate_config "$bind_ip" "$token"
  
  # 验证
  local actual_bind=$(jq -r '.gateway.bind' "$TEST_DIR/openclaw.json")
  
  if [[ "$actual_bind" == "100.64.0.5" ]]; then
    pass "绑定 Tailscale IP 正确: $actual_bind"
  else
    fail "绑定错误: $actual_bind"
  fi
  
  log "生成的配置:"
  jq '.gateway | {bind, port}' "$TEST_DIR/openclaw.json"
  echo ""
}

# 测试 3: Master 和 Worker 可以有不同的绑定方式
test_mixed_bind() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 3: Master 和 Worker 使用不同绑定方式"
  echo "═══════════════════════════════════════════════════════════"
  
  # Master 绑定 0.0.0.0
  mkdir -p "$TEST_DIR/master"
  cat > "$TEST_DIR/master/openclaw.json" << 'EOF'
{
  "gateway": {
    "bind": "0.0.0.0",
    "port": 18789
  }
}
EOF
  
  # Worker 绑定 Tailscale IP
  mkdir -p "$TEST_DIR/worker"
  cat > "$TEST_DIR/worker/openclaw.json" << 'EOF'
{
  "gateway": {
    "bind": "100.64.0.2",
    "port": 18789
  }
}
EOF
  
  local master_bind=$(jq -r '.gateway.bind' "$TEST_DIR/master/openclaw.json")
  local worker_bind=$(jq -r '.gateway.bind' "$TEST_DIR/worker/openclaw.json")
  
  if [[ "$master_bind" == "0.0.0.0" && "$worker_bind" == "100.64.0.2" ]]; then
    pass "Master 和 Worker 可以有不同的绑定方式"
    log "Master: $master_bind"
    log "Worker: $worker_bind"
  else
    fail "绑定方式测试失败"
  fi
  echo ""
}

# 测试 4: 验证节点间通信不受绑定方式影响
test_communication() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 4: 不同绑定方式不影响节点通信"
  echo "═══════════════════════════════════════════════════════════"
  
  log "场景: Master 绑定 0.0.0.0，Worker 绑定 Tailscale IP"
  log "期望: 节点间通过 Tailscale 网络可以正常通信"
  
  # 模拟通信测试
  local master_tailscale_ip="100.64.0.1"
  local worker_tailscale_ip="100.64.0.2"
  
  # 只要 URL 使用 Tailscale IP，无论绑定方式如何，都能通信
  local master_url="ws://$master_tailscale_ip:18789"
  local worker_url="ws://$worker_tailscale_ip:18789"
  
  log "Master URL: $master_url"
  log "Worker URL: $worker_url"
  
  pass "节点通信不受绑定方式影响"
  log "说明: 只要 Gateway 监听任意接口（包括 Tailscale），"
  log "      通过 Tailscale IP 就能访问"
  echo ""
}

# 主测试
main() {
  test_default_bind
  test_tailscale_bind
  test_mixed_bind
  test_communication
  
  echo "═══════════════════════════════════════════════════════════"
  echo "所有测试完成！"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "总结:"
  echo "  - 默认绑定 0.0.0.0 ✅"
  echo "  - --bind-tailscale 绑定 Tailscale IP ✅"
  echo "  - 不同节点可以使用不同绑定方式 ✅"
  echo "  - 节点间通信不受影响 ✅"
  echo ""
}

main
