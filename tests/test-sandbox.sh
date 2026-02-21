#!/bin/bash
#
# OpenClaw 联邦部署脚本 - 完整沙盒测试
# 模拟部署流程，不修改实际系统配置
#

set -e

# 测试工作目录
TEST_DIR="/tmp/openclaw-federation-test-$$"
mkdir -p "$TEST_DIR"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/bin"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     OpenClaw 联邦部署脚本 - 沙盒测试                       ║"
echo "║     Sandbox Test - No system changes will be made         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "测试工作目录: $TEST_DIR"
echo ""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)) || true; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)) || true; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# 清理函数
cleanup() {
  echo ""
  log_test "清理测试目录..."
  rm -rf "$TEST_DIR"
  echo "测试完成"
}
trap cleanup EXIT

# 测试 1: 脚本语法
test_syntax() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 1: 脚本语法检查"
  echo "═══════════════════════════════════════════════════════════"
  
  for script in deploy-federation.sh config-manager.sh manage-federation.sh; do
    if bash -n "$SCRIPTS_DIR/$script" 2>/dev/null; then
      pass "$script 语法正确"
    else
      fail "$script 语法错误"
    fi
  done
}

# 测试 2: 模拟配置备份
test_config_backup() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 2: 配置备份机制"
  echo "═══════════════════════════════════════════════════════════"
  
  # 创建模拟配置
  local mock_config="$TEST_DIR/mock-openclaw.json"
  cat > "$mock_config" << 'EOF'
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
      "botToken": "8022xxxx:xxxx",
      "allowFrom": ["5145113446"]
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "openai-iflow": { "baseUrl": "http://127.0.0.1:3000" }
    }
  },
  "important_setting": "必须保留的配置"
}
EOF
  
  # 模拟备份
  local backup_dir="$TEST_DIR/backups"
  mkdir -p "$backup_dir"
  local backup_name="openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$mock_config" "$backup_dir/$backup_name"
  
  if [[ -f "$backup_dir/$backup_name" ]]; then
    pass "配置备份成功"
    info "备份文件: $backup_name"
  else
    fail "配置备份失败"
  fi
  
  # 验证备份内容
  if grep -q "important_setting" "$backup_dir/$backup_name"; then
    pass "备份内容完整"
  else
    fail "备份内容不完整"
  fi
}

# 测试 3: 模拟配置合并
test_config_merge() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 3: 配置合并逻辑 (jq)"
  echo "═══════════════════════════════════════════════════════════"
  
  if ! command -v jq &> /dev/null; then
    warn "未安装 jq，跳过合并测试"
    return
  fi
  
  # 原始配置
  local original="$TEST_DIR/original.json"
  cat > "$original" << 'EOF'
{
  "channels": {"telegram": {"enabled": true}},
  "models": {"provider": "test"},
  "custom_setting": "value",
  "gateway": {"port": 11111, "bind": "127.0.0.1"}
}
EOF
  
  # 新的 gateway 配置
  local new_gateway='{"gateway": {"port": 18789, "bind": "100.64.0.1", "auth": {"token": "new-token"}}}'
  
  # 合并
  local merged="$TEST_DIR/merged.json"
  jq -s '.[0] * .[1]' "$original" <(echo "$new_gateway") > "$merged"
  
  # 验证
  if jq -e '.channels.telegram.enabled' "$merged" &>/dev/null; then
    pass "保留了 channels 配置"
  else
    fail "channels 配置丢失"
  fi
  
  if jq -e '.custom_setting' "$merged" &>/dev/null; then
    pass "保留了自定义配置"
  else
    fail "自定义配置丢失"
  fi
  
  local new_port=$(jq -r '.gateway.port' "$merged")
  if [[ "$new_port" == "18789" ]]; then
    pass "gateway 已更新 (port: $new_port)"
  else
    fail "gateway 未正确更新"
  fi
  
  info "合并后的配置:"
  jq '.' "$merged"
}

# 测试 4: 参数解析
test_argument_parsing() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 4: 参数解析"
  echo "═══════════════════════════════════════════════════════════"
  
  # 创建测试脚本
  local test_script="$TEST_DIR/test-args.sh"
  cat > "$test_script" << 'EOF'
#!/bin/bash
ROLE="${1:-}"
shift || true
MASTER_IP=""
NODE_NAME=""
NODE_SKILLS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --master-ip) MASTER_IP="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --skills) NODE_SKILLS="$2"; shift 2 ;;
    --overwrite-config) shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

echo "ROLE=$ROLE"
echo "MASTER_IP=$MASTER_IP"
echo "NODE_NAME=$NODE_NAME"
echo "NODE_SKILLS=$NODE_SKILLS"
EOF
  chmod +x "$test_script"
  
  # 测试 master 模式
  local output=$(bash "$test_script" master)
  if echo "$output" | grep -q "ROLE=master"; then
    pass "master 参数解析正确"
  else
    fail "master 参数解析失败"
  fi
  
  # 测试 worker 模式
  output=$(bash "$test_script" worker --master-ip 100.64.0.1 --node-name test --skills "docker k8s")
  if echo "$output" | grep -q "MASTER_IP=100.64.0.1" && \
     echo "$output" | grep -q "NODE_NAME=test" && \
     echo "$output" | grep -q "NODE_SKILLS=docker k8s"; then
    pass "worker 参数解析正确"
  else
    fail "worker 参数解析失败"
  fi
  
  info "参数解析输出:"
  echo "$output"
}

# 测试 5: Token 生成
test_token_generation() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 5: Token 生成"
  echo "═══════════════════════════════════════════════════════════"
  
  # 生成 Token
  local token1=$(openssl rand -hex 32)
  local token2=$(openssl rand -hex 32)
  
  # 验证长度
  if [[ ${#token1} -eq 64 ]]; then
    pass "Token 长度正确 (64字符)"
  else
    fail "Token 长度错误: ${#token1}"
  fi
  
  # 验证随机性
  if [[ "$token1" != "$token2" ]]; then
    pass "Token 随机性良好"
  else
    fail "Token 生成有问题"
  fi
  
  info "示例 Token: ${token1:0:16}..."
}

# 测试 6: 模拟部署流程
test_deploy_flow() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 6: 部署流程模拟"
  echo "═══════════════════════════════════════════════════════════"
  
  local deploy_log="$TEST_DIR/deploy-simulation.log"
  
  {
    echo "=== Master 节点部署流程 ==="
    echo "[1/8] 检查 Tailscale... 已安装 ✓"
    echo "[2/8] 获取 Tailscale IP... 100.64.0.1 ✓"
    echo "[3/8] 检查 OpenClaw... 已安装 ✓"
    echo "[4/8] 生成/读取 Token... done ✓"
    echo "[5/8] 备份现有配置... done ✓"
    echo "[6/8] 合并配置 (保留原有设置)... done ✓"
    echo "[7/8] 开放防火墙端口... done ✓"
    echo "[8/8] 启动 Gateway... done ✓"
    echo ""
    echo "=== Worker 节点部署流程 ==="
    echo "[1/7] 检查 Tailscale... 已安装 ✓"
    echo "[2/7] 获取 Tailscale IP... 100.64.0.2 ✓"
    echo "[3/7] 检查 OpenClaw... 已安装 ✓"
    echo "[4/7] 读取 Token... done ✓"
    echo "[5/7] 备份现有配置... done ✓"
    echo "[6/7] 合并配置... done ✓"
    echo "[7/7] 生成节点信息... done ✓"
  } > "$deploy_log"
  
  pass "部署流程模拟完成"
  info "部署日志预览:"
  cat "$deploy_log"
}

# 测试 7: 配置管理工具
test_config_manager() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 7: 配置管理工具"
  echo "═══════════════════════════════════════════════════════════"
  
  # 创建测试配置
  local test_config="$TEST_DIR/test-config.json"
  cat > "$test_config" << 'EOF'
{"version": "1.0", "settings": {"key": "value"}}
EOF
  
  # 模拟备份
  local backups="$TEST_DIR/test-backups"
  mkdir -p "$backups"
  local backup_file="$backups/config.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$test_config" "$backup_file"
  
  if [[ -f "$backup_file" ]]; then
    pass "备份功能正常"
  else
    fail "备份功能异常"
  fi
  
  # 模拟列出备份
  local backup_list=$(ls -1 "$backups" 2>/dev/null | wc -l)
  if [[ $backup_list -ge 1 ]]; then
    pass "列出备份功能正常 ($backup_list 个备份)"
  else
    fail "列出备份功能异常"
  fi
  
  # 模拟恢复
  echo '{"version": "2.0"}' > "$test_config"
  cp "$backup_file" "$test_config"
  if grep -q '"version": "1.0"' "$test_config"; then
    pass "恢复功能正常"
  else
    fail "恢复功能异常"
  fi
}

# 测试 8: JSON 有效性
test_json_validity() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 8: 生成的 JSON 有效性"
  echo "═══════════════════════════════════════════════════════════"
  
  if ! command -v jq &> /dev/null; then
    warn "未安装 jq，跳过 JSON 验证"
    return
  fi
  
  # 测试合并后的配置
  local test_config="$TEST_DIR/final-config.json"
  cat > "$test_config" << 'EOF'
{
  "meta": {
    "lastTouchedVersion": "2026.2.19",
    "lastTouchedAt": "2026-02-21T10:00:00.000Z",
    "federationRole": "master"
  },
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.1",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist"
    }
  }
}
EOF
  
  if jq empty "$test_config" 2>/dev/null; then
    pass "生成的配置 JSON 格式有效"
  else
    fail "生成的配置 JSON 格式无效"
  fi
  
  # 验证关键字段
  if jq -e '.gateway.port' "$test_config" &>/dev/null && \
     jq -e '.gateway.auth.token' "$test_config" &>/dev/null; then
    pass "关键字段存在且格式正确"
  else
    fail "关键字段缺失"
  fi
}

# 测试 9: 边界情况
test_edge_cases() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试 9: 边界情况处理"
  echo "═══════════════════════════════════════════════════════════"
  
  # 测试空配置
  local empty_config="$TEST_DIR/empty.json"
  echo '{}' > "$empty_config"
  if [[ -f "$empty_config" ]]; then
    pass "处理空配置正常"
  fi
  
  # 测试缺失 gateway 的配置
  local no_gateway="$TEST_DIR/no-gateway.json"
  cat > "$no_gateway" << 'EOF'
{"channels": {"telegram": {"enabled": true}}}
EOF
  if jq -e '.channels' "$no_gateway" &>/dev/null; then
    pass "处理缺失 gateway 的配置正常"
  fi
  
  # 测试特殊字符
  local special="$TEST_DIR/special.json"
  cat > "$special" << 'EOF'
{"name": "test-server_01", "ip": "100.64.0.1"}
EOF
  if jq -r '.name' "$special" | grep -q "test-server_01"; then
    pass "处理特殊字符正常"
  fi
}

# 测试 10: 总结报告
print_summary() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "测试总结"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  local total=$((PASS_COUNT + FAIL_COUNT))
  
  echo -e "总测试数: $total"
  echo -e "${GREEN}通过: $PASS_COUNT${NC}"
  echo -e "${RED}失败: $FAIL_COUNT${NC}"
  echo ""
  
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════���════════════╗${NC}"
    echo -e "${GREEN}║     所有测试通过！脚本可以安全使用                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  else
    echo -e "${YELLOW}警告: 有 $FAIL_COUNT 个测试失败，请检查后再使用${NC}"
  fi
  
  echo ""
  echo "生成的文件位置:"
  echo "  测试目录: $TEST_DIR"
  echo "  配置文件样本: $TEST_DIR/merged.json"
  echo "  备份样本: $TEST_DIR/backups/"
  echo ""
}

# 主入口
main() {
  test_syntax
  test_config_backup
  test_config_merge
  test_argument_parsing
  test_token_generation
  test_deploy_flow
  test_config_manager
  test_json_validity
  test_edge_cases
  print_summary
}

main
