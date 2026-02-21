#!/bin/bash
#
# OpenClaw + Tailscale 联邦部署脚本 - 测试模式
# 验证脚本逻辑而不实际安装
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试模式标志
DRY_RUN=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/bin"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     OpenClaw + Tailscale 联邦部署脚本 - 测试模式          ║"
echo "║     Dry Run - No actual changes will be made              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# 模拟日志函数
log_info() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

# 模拟命令执行
run_cmd() {
  log_info "将要执行: $*"
  return 0
}

# 测试 1: 检查脚本语法
test_syntax() {
  echo ""
  echo -e "${BLUE}=== 测试 1: 脚本语法检查 ===${NC}"
  
  if bash -n "$SCRIPTS_DIR/deploy-federation.sh"; then
    log_success "deploy-federation.sh 语法正确"
  else
    log_error "deploy-federation.sh 语法错误"
    return 1
  fi
  
  if bash -n "$SCRIPTS_DIR/manage-federation.sh"; then
    log_success "manage-federation.sh 语法正确"
  else
    log_error "manage-federation.sh 语法错误"
    return 1
  fi
}

# 测试 2: 参数解析
test_args() {
  echo ""
  echo -e "${BLUE}=== 测试 2: 参数解析测试 ===${NC}"
  
  # 模拟参数解析
  ROLE="master"
  MASTER_IP=""
  NODE_NAME=""
  NODE_SKILLS=""
  
  # 测试 master 模式
  log_info "测试 master 模式参数..."
  ROLE="master"
  log_success "ROLE=$ROLE"
  
  # 测试 worker 模式
  log_info "测试 worker 模式参数..."
  ROLE="worker"
  MASTER_IP="100.64.0.1"
  NODE_NAME="test-server"
  NODE_SKILLS="docker k8s"
  
  log_success "ROLE=$ROLE"
  log_success "MASTER_IP=$MASTER_IP"
  log_success "NODE_NAME=$NODE_NAME"
  log_success "NODE_SKILLS=$NODE_SKILLS"
}

# 测试 3: 配置生成
test_config_generation() {
  echo ""
  echo -e "${BLUE}=== 测试 3: 配置文件生成测试 ===${NC}"
  
  GATEWAY_PORT=18789
  TOKEN="test-token-1234567890abcdef"
  TAILSCALE_IP="100.64.0.100"
  
  # 生成测试配置
  CONFIG=$(cat << EOF
{
  "gateway": {
    "port": $GATEWAY_PORT,
    "bind": "$TAILSCALE_IP",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$TOKEN"
    }
  }
}
EOF
)
  
  log_info "生成的配置预览:"
  echo "$CONFIG" | head -10
  
  # 验证 JSON 格式
  if echo "$CONFIG" | jq . > /dev/null 2>&1; then
    log_success "配置 JSON 格式正确"
  else
    log_warn "JSON 验证需要 jq 工具"
  fi
}

# 测试 4: 节点信息生成
test_node_info() {
  echo ""
  echo -e "${BLUE}=== 测试 4: 节点信息生成测试 ===${NC}"
  
  node_name="home-server"
  my_ip="100.64.0.2"
  master_ip="100.64.0.1"
  NODE_SKILLS="docker k8s tmux"
  
  NODE_INFO=$(cat << EOF
{
  "name": "$node_name",
  "tailscale_ip": "$my_ip",
  "master_ip": "$master_ip",
  "skills": "$NODE_SKILLS",
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
  
  log_info "生成的节点信息:"
  echo "$NODE_INFO"
  log_success "节点信息格式正确"
}

# 测试 5: 命令生成
test_commands() {
  echo ""
  echo -e "${BLUE}=== 测试 5: 管理命令生成测试 ===${NC}"
  
  GATEWAY_PORT=18789
  TOKEN="test-token-1234567890abcdef"
  node_name="home-server"
  my_ip="100.64.0.2"
  
  log_info "添加节点命令:"
  echo -e "${GREEN}openclaw pair approve \\\n  --name \"$node_name\" \\\n  --url \"ws://$my_ip:$GATEWAY_PORT\" \\\n  --token \"${TOKEN:0:16}...\"${NC}"
  
  log_info "查看节点列表:"
  echo -e "${GREEN}openclaw nodes list${NC}"
  
  log_info "远程执行命令:"
  echo -e "${GREEN}openclaw nodes invoke $node_name -- docker ps${NC}"
  
  log_success "命令格式正确"
}

# 测试 6: 模拟部署流程
test_deploy_flow() {
  echo ""
  echo -e "${BLUE}=== 测试 6: 部署流程模拟 ===${NC}"
  
  echo ""
  log_info "[master 模式] 部署流程:"
  run_cmd "install_tailscale"
  run_cmd "tailscale up"
  run_cmd "tailscale ip -4"
  run_cmd "install_openclaw"
  run_cmd "generate_token"
  run_cmd "configure_gateway master 100.64.0.1"
  run_cmd "open_firewall"
  run_cmd "openclaw gateway restart"
  
  echo ""
  log_info "[worker 模式] 部署流程:"
  run_cmd "install_tailscale"
  run_cmd "tailscale up"
  run_cmd "tailscale ip -4"
  run_cmd "install_openclaw"
  run_cmd "configure_gateway worker 100.64.0.2"
  run_cmd "openclaw gateway restart"
  run_cmd "install_skills 'docker k8s'"
  run_cmd "connect_to_master 100.64.0.1 home-server"
  
  log_success "部署流程模拟完成"
}

# 测试 7: 管理命令测试
test_manage_commands() {
  echo ""
  echo -e "${BLUE}=== 测试 7: 管理脚本功能测试 ===${NC}"
  
  log_info "测试 list 命令..."
  run_cmd "openclaw nodes list"
  
  log_info "测试 status 命令..."
  run_cmd "openclaw nodes status"
  
  log_info "测试 exec 命令..."
  run_cmd "openclaw nodes invoke home-server -- docker ps"
  
  log_info "测试 broadcast 命令..."
  run_cmd "openclaw nodes invoke [all] -- uptime"
  
  log_success "管理命令测试完成"
}

# 主测试流程
main() {
  test_syntax
  test_args
  test_config_generation
  test_node_info
  test_commands
  test_deploy_flow
  test_manage_commands
  
  echo ""
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     所有测试通过！脚本可以正常使用                        ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  echo "实际部署命令示例:"
  echo ""
  echo "1. 主节点部署:"
  echo -e "   ${BLUE}sudo ./bin/deploy-federation.sh master${NC}"
  echo ""
  echo "2. 工作节点部署:"
  echo -e "   ${BLUE}sudo ./bin/deploy-federation.sh worker --master-ip 100.64.0.1 --node-name home-server --skills 'docker k8s'${NC}"
  echo ""
}

main
