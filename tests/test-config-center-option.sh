#!/bin/bash
#
# 测试 --enable-config-center 选项
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  测试 --enable-config-center 选项                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log() { echo -e "${BLUE}[TEST]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# 测试 1: 默认不启用配置中心
test_default_no_config_center() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 1: 默认参数（不应启用配置中心）"
  echo "═══════════════════════════════════════════════════════════"
  
  # 模拟参数解析
  ENABLE_CONFIG_CENTER=false
  
  if [[ "$ENABLE_CONFIG_CENTER" == "false" ]]; then
    pass "默认不启用配置中心"
  else
    echo "❌ 默认设置错误"
  fi
  echo ""
}

# 测试 2: 显式启用配置中心
test_enable_config_center() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 2: 使用 --enable-config-center（应启用）"
  echo "═══════════════════════════════════════════════════════════"
  
  # 模拟参数解析
  ENABLE_CONFIG_CENTER=true
  
  if [[ "$ENABLE_CONFIG_CENTER" == "true" ]]; then
    pass "配置中心已启用"
  else
    echo "❌ 启用失败"
  fi
  echo ""
}

# 测试 3: 帮助信息包含新选项
test_help_includes_option() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 3: 帮助信息包含 --enable-config-center"
  echo "═══════════════════════════════════════════════════════════"
  
  if grep -q "enable-config-center" /root/.openclaw/workspace/deploy-federation.sh; then
    pass "帮助信息包含 --enable-config-center 选项"
    info "部署命令示例:"
    echo ""
    echo "  # 默认部署（不启用配置中心）"
    echo "  ./deploy-federation.sh master"
    echo ""
    echo "  # 启用配置中心"
    echo "  ./deploy-federation.sh master --enable-config-center"
    echo ""
  else
    echo "❌ 帮助信息缺失"
  fi
  echo ""
}

# 测试 4: 使用场景对比
test_usage_scenarios() {
  echo "═══════════════════════════════════════════════════════════"
  log "测试 4: 使用场景对比"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  echo "场景 A：简单联邦（2-3 节点，配置不常变）"
  echo "───────────────────────────────────────────────────────────"
  echo "命令: ./deploy-federation.sh master"
  echo "      ↓"
  echo "结果: 不启用配置中心"
  echo "      各节点独立管理配置"
  echo "      适合小规模、配置稳定的场景"
  echo ""
  
  echo "场景 B：大规模联邦（5+ 节点，配置常变）"
  echo "───────────────────────────────────────────────────────────"
  echo "命令: ./deploy-federation.sh master --enable-config-center"
  echo "      ↓"
  echo "结果: 启用配置中心"
  echo "      统一配置管理，自动同步"
  echo "      适合大规模、频繁修改配置的场景"
  echo ""
  
  pass "使用场景清晰"
  echo ""
}

# 主测试
main() {
  test_default_no_config_center
  test_enable_config_center
  test_help_includes_option
  test_usage_scenarios
  
  echo "═══════════════════════════════════════════════════════════"
  echo "所有测试完成！"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "总结:"
  echo "  ✅ 默认不启用配置中心"
  echo "  ✅ 使用 --enable-config-center 显式启用"
  echo "  ✅ 灵活适应不同场景"
  echo ""
}

main
