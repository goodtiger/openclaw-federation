#!/bin/bash
#
# OpenClaw 联邦自动注册脚本
# Worker 节点启动时自动向 Master 注册
#

set -e

# 配置
TOKEN_FILE="/root/.openclaw/.federation-token"
CONFIG_FILE="/root/.openclaw/.federation-config.json"
NODE_INFO_FILE="/root/.openclaw/.node-info.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

now_iso() {
  if date -Iseconds >/dev/null 2>&1; then
    date -Iseconds
  else
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

# 获取本机信息
gather_node_info() {
  # 节点名称
  local node_name
  if [[ -f "$NODE_INFO_FILE" ]]; then
    node_name=$(jq -r '.name' "$NODE_INFO_FILE" 2>/dev/null)
  fi
  [[ -z "$node_name" || "$node_name" == "null" ]] && node_name=$(hostname -s)
  
  # Tailscale IP
  local tailscale_ip
  tailscale_ip=$(tailscale ip -4 2>/dev/null | head -1)
  if [[ -z "$tailscale_ip" ]]; then
    log_error "无法获取 Tailscale IP，请确保 Tailscale 已启动"
    exit 1
  fi
  
  # 技能列表
  local skills=""
  if [[ -f "$NODE_INFO_FILE" ]]; then
    skills=$(jq -r '.skills' "$NODE_INFO_FILE" 2>/dev/null)
  fi
  [[ "$skills" == "null" ]] && skills=""
  
  # 系统信息
  local os=$(uname -s)
  local arch=$(uname -m)
  
  # 生成注册信息
  cat > /tmp/node-registration.json << EOF
{
  "name": "$node_name",
  "url": "ws://${tailscale_ip}:18789",
  "ip": "$tailscale_ip",
  "skills": "$skills",
  "system": {
    "os": "$os",
    "arch": "$arch"
  },
  "registered_at": "$(now_iso)"
}
EOF
  
  echo "节点名称: $node_name"
  echo "Tailscale IP: $tailscale_ip"
  echo "技能: $skills"
}

# 向 Master 注册
register_to_master() {
  local master_ip=$1
  local token=$2
  
  log_info "向 Master ($master_ip) 注册..."
  
  # 检查是否已注册
  if check_already_registered "$master_ip" "$token"; then
    log_success "节点已在 Master 上注册"
    return 0
  fi
  
  # 发送注册请求
  local response
  local http_code
  
  http_code=$(curl -s -o /tmp/register-response.txt -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 10 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d @/tmp/node-registration.json \
    "http://${master_ip}:18789/api/nodes/register" 2>/dev/null || echo "000")
  
  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    log_success "注册成功！"
    cat /tmp/register-response.txt | jq . 2>/dev/null || cat /tmp/register-response.txt
    return 0
  elif [[ "$http_code" == "409" ]]; then
    log_warn "节点已存在，跳过注册"
    return 0
  else
    log_error "注册失败 (HTTP $http_code)"
    cat /tmp/register-response.txt 2>/dev/null || echo "无响应"
    return 1
  fi
}

# 检查是否已注册
check_already_registered() {
  local master_ip=$1
  local token=$2
  
  # 获取节点名称
  local node_name
  node_name=$(jq -r '.name' /tmp/node-registration.json 2>/dev/null)
  
  # 查询 Master 的节点列表
  local nodes
  nodes=$(curl -s \
    --connect-timeout 5 \
    -H "Authorization: Bearer $token" \
    "http://${master_ip}:18789/api/nodes" 2>/dev/null || echo "[]")
  
  # 检查节点名是否已存在
  if echo "$nodes" | jq -e ".[] | select(.name == \"$node_name\")" > /dev/null 2>&1; then
    return 0  # 已注册
  fi
  
  return 1  # 未注册
}

# 自动发现 Master
auto_discover_master() {
  log_info "尝试自动发现 Master..."
  
  # 方法 1: 从配置文件读取
  if [[ -f "$CONFIG_FILE" ]]; then
    local master_ip
    master_ip=$(jq -r '.master_ip' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$master_ip" && "$master_ip" != "null" ]]; then
      log_success "从配置文件发现 Master: $master_ip"
      echo "$master_ip"
      return 0
    fi
  fi
  
  # 方法 2: 从环境变量
  if [[ -n "${FEDERATION_MASTER_IP:-}" ]]; then
    log_success "从环境变量发现 Master: $FEDERATION_MASTER_IP"
    echo "$FEDERATION_MASTER_IP"
    return 0
  fi
  
  # 方法 3: 从 Tailscale 网络扫描（简化版）
  log_warn "无法自动发现 Master，请手动指定 --master-ip"
  return 1
}

# 保存配置
save_config() {
  local master_ip=$1
  
  mkdir -p "$(dirname "$CONFIG_FILE")"
  
  cat > "$CONFIG_FILE" << EOF
{
  "master_ip": "$master_ip",
  "registered_at": "$(now_iso)",
  "auto_register": true
}
EOF
  
  chmod 600 "$CONFIG_FILE"
}

# 主注册流程
main() {
  local master_ip="${1:-}"
  local token="${2:-}"
  
  echo "═══════════════════════════════════════════════════════════"
  echo "OpenClaw 联邦自动注册"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  # 1. 收集节点信息
  log_info "收集节点信息..."
  gather_node_info
  echo ""
  
  # 2. 获取 Master IP
  if [[ -z "$master_ip" ]]; then
    master_ip=$(auto_discover_master)
    [[ -z "$master_ip" ]] && { log_error "未指定 Master IP"; exit 1; }
  fi
  log_info "Master IP: $master_ip"
  
  # 3. 获取 Token
  if [[ -z "$token" ]]; then
    if [[ -f "$TOKEN_FILE" ]]; then
      token=$(cat "$TOKEN_FILE")
      log_info "从文件读取 Token"
    else
      log_error "未找到 Token 文件: $TOKEN_FILE"
      log_info "请先获取 Token 并保存到该文件"
      exit 1
    fi
  fi
  
  # 4. 注册
  if register_to_master "$master_ip" "$token"; then
    # 保存配置
    save_config "$master_ip"
    log_success "注册流程完成！"
    echo ""
    log_info "配置文件已保存到: $CONFIG_FILE"
  else
    log_error "注册失败"
    exit 1
  fi
  
  # 5. 显示状态
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "注册信息:"
  echo "═══════════════════════════════════════════════════════════"
  cat /tmp/node-registration.json | jq .
  
  # 清理临时文件
  rm -f /tmp/node-registration.json /tmp/register-response.txt
}

# 帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦自动注册工具

用法:
  auto-register.sh [MASTER_IP] [TOKEN]

参数:
  MASTER_IP    Master 节点的 Tailscale IP（可选，也可自动发现）
  TOKEN        共享 Token（可选，默认从文件读取）

示例:
  # 自动发现 Master 并注册
  ./auto-register.sh

  # 指定 Master IP 注册
  ./auto-register.sh 100.64.0.1

  # 指定 Master IP 和 Token
  ./auto-register.sh 100.64.0.1 "your-token-here"

环境变量:
  FEDERATION_MASTER_IP    Master IP（优先级高于自动发现）

注意:
  需要先运行 deploy-federation.sh worker 完成基础部署
  本脚本仅负责向 Master 注册节点

EOF
}

# 入口
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

main "$@"
