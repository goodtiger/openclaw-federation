#!/bin/bash
#
# OpenClaw 联邦自动注册脚本
# Worker 节点启动时自动向 Master 注册
#

set -euo pipefail

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

resolve_openclaw_home() {
  if [[ -n "${OPENCLAW_HOME:-}" ]]; then
    echo "$OPENCLAW_HOME"
    return 0
  fi

  local user_home="$HOME"
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    if command -v getent &> /dev/null; then
      user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    elif [[ -d "/Users/$SUDO_USER" ]]; then
      user_home="/Users/$SUDO_USER"
    elif [[ -d "/home/$SUDO_USER" ]]; then
      user_home="/home/$SUDO_USER"
    fi
  fi
  echo "$user_home/.openclaw"
}

OPENCLAW_HOME="$(resolve_openclaw_home)"
DEFAULT_TOKEN_FILE="$OPENCLAW_HOME/.federation-token"
TOKEN_FILE="${TOKEN_FILE:-$DEFAULT_TOKEN_FILE}"
CONFIG_FILE="${CONFIG_FILE:-$OPENCLAW_HOME/.federation-config.json}"
NODE_INFO_FILE="${NODE_INFO_FILE:-$OPENCLAW_HOME/.node-info.json}"

SUDO_CMD=""
init_privilege() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
      SUDO_CMD="sudo"
    fi
  fi
}

now_iso() {
  if date -Iseconds >/dev/null 2>&1; then
    date -Iseconds
  else
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

need_cmd() {
  local cmd=$1
  command -v "$cmd" &>/dev/null
}

tailscale_ip4() {
  local ip=""
  ip=$(tailscale ip -4 2>/dev/null | head -1 || true)
  if [[ -z "$ip" && -n "$SUDO_CMD" ]]; then
    ip=$($SUDO_CMD tailscale ip -4 2>/dev/null | head -1 || true)
  fi
  echo "$ip"
}

read_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    log_error "未找到 Token 文件: $TOKEN_FILE"
    exit 1
  fi
  local token
  token=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
  if [[ -z "$token" ]]; then
    log_error "Token 文件为空: $TOKEN_FILE"
    exit 1
  fi
  echo "$token"
}

# 临时文件（使用 mktemp + trap 清理）
NODE_REG_FILE=""
RESP_FILE=""
cleanup() {
  [[ -n "${NODE_REG_FILE:-}" ]] && rm -f "$NODE_REG_FILE" 2>/dev/null || true
  [[ -n "${RESP_FILE:-}" ]] && rm -f "$RESP_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# 获取本机信息并写入注册 JSON
# 输出：node_name, tailscale_ip, skills
# 写入：$NODE_REG_FILE

gather_node_info() {
  local node_name=""
  local skills=""

  if [[ -f "$NODE_INFO_FILE" ]] && need_cmd jq; then
    node_name=$(jq -r '.name // empty' "$NODE_INFO_FILE" 2>/dev/null || true)
    skills=$(jq -r '.skills // empty' "$NODE_INFO_FILE" 2>/dev/null || true)
  fi

  [[ -z "$node_name" ]] && node_name=$(hostname -s)

  local ts_ip
  ts_ip="$(tailscale_ip4)"
  if [[ -z "$ts_ip" ]]; then
    log_error "无法获取 Tailscale IP，请确保 Tailscale 已启动并已登录"
    exit 1
  fi

  local os arch
  os=$(uname -s)
  arch=$(uname -m)

  umask 077
  NODE_REG_FILE=$(mktemp)

  cat > "$NODE_REG_FILE" << EOF
{
  "name": "$node_name",
  "url": "ws://${ts_ip}:18789",
  "ip": "$ts_ip",
  "skills": "$skills",
  "system": {
    "os": "$os",
    "arch": "$arch"
  },
  "registered_at": "$(now_iso)"
}
EOF

  echo "$node_name|$ts_ip|$skills"
}

# 检查是否已注册（有 jq 时才做）
check_already_registered() {
  local master_ip=$1
  local token=$2

  if ! need_cmd jq; then
    return 1
  fi

  local node_name
  node_name=$(jq -r '.name // empty' "$NODE_REG_FILE" 2>/dev/null || true)
  [[ -z "$node_name" ]] && return 1

  local nodes
  nodes=$(curl -s --connect-timeout 5 --max-time 8 \
    -H "Authorization: Bearer $token" \
    "http://${master_ip}:18789/api/nodes" 2>/dev/null || echo "[]")

  echo "$nodes" | jq -e --arg n "$node_name" '.[] | select(.name == $n)' >/dev/null 2>&1
}

register_to_master() {
  local master_ip=$1
  local token=$2

  log_info "向 Master ($master_ip) 注册..."

  if check_already_registered "$master_ip" "$token"; then
    log_success "节点已在 Master 上注册"
    return 0
  fi

  RESP_FILE=$(mktemp)

  local http_code
  http_code=$(curl -s -o "$RESP_FILE" -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d @"$NODE_REG_FILE" \
    "http://${master_ip}:18789/api/nodes/register" 2>/dev/null || echo "000")

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    log_success "注册成功！"
    if need_cmd jq; then
      jq . "$RESP_FILE" 2>/dev/null || cat "$RESP_FILE"
    else
      cat "$RESP_FILE"
    fi
    return 0
  elif [[ "$http_code" == "409" ]]; then
    log_warn "节点已存在（HTTP 409），跳过注册"
    return 0
  else
    log_error "注册失败 (HTTP $http_code)"
    cat "$RESP_FILE" 2>/dev/null || echo "无响应"
    return 1
  fi
}

# 自动发现 Master
auto_discover_master() {
  # 1) 先从 NODE_INFO_FILE 读取（deploy-federation.sh 会写 master_ip）
  if [[ -f "$NODE_INFO_FILE" ]] && need_cmd jq; then
    local master_ip
    master_ip=$(jq -r '.master_ip // empty' "$NODE_INFO_FILE" 2>/dev/null || true)
    if [[ -n "$master_ip" ]]; then
      log_success "从 $NODE_INFO_FILE 发现 Master: $master_ip"
      echo "$master_ip"
      return 0
    fi
  fi

  # 2) 配置文件
  if [[ -f "$CONFIG_FILE" ]] && need_cmd jq; then
    local master_ip
    master_ip=$(jq -r '.master_ip // empty' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -n "$master_ip" ]]; then
      log_success "从配置文件发现 Master: $master_ip"
      echo "$master_ip"
      return 0
    fi
  fi

  # 3) 环境变量
  if [[ -n "${FEDERATION_MASTER_IP:-}" ]]; then
    log_success "从环境变量发现 Master: $FEDERATION_MASTER_IP"
    echo "$FEDERATION_MASTER_IP"
    return 0
  fi

  log_warn "无法自动发现 Master，请手动指定 master_ip"
  return 1
}

save_config() {
  local master_ip=$1

  mkdir -p "$(dirname "$CONFIG_FILE")"

  umask 077
  cat > "$CONFIG_FILE" << EOF
{
  "master_ip": "$master_ip",
  "registered_at": "$(now_iso)",
  "auto_register": true
}
EOF

  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
}

show_help() {
  cat << 'EOF'
OpenClaw 联邦自动注册工具

用法:
  auto-register.sh [MASTER_IP] [TOKEN]

参数:
  MASTER_IP    Master 节点的 Tailscale IP（可选，也可自动发现）
  TOKEN        共享 Token（可选，默认从 TOKEN_FILE 读取）

环境变量:
  OPENCLAW_HOME           OpenClaw 目录（默认: ~/.openclaw 或 sudo 用户家目录）
  TOKEN_FILE              Token 文件路径（默认: $OPENCLAW_HOME/.federation-token）
  CONFIG_FILE             配置文件路径（默认: $OPENCLAW_HOME/.federation-config.json）
  NODE_INFO_FILE          节点信息文件（默认: $OPENCLAW_HOME/.node-info.json）
  FEDERATION_MASTER_IP    Master IP（优先级高于自动发现）

注意:
  需要先运行 deploy-federation.sh worker 完成基础部署
  本脚本仅负责向 Master 注册节点
EOF
}

main() {
  init_privilege

  local master_ip="${1:-}"
  local token="${2:-}"

  echo "═══════════════════════════════════════════════════════════"
  echo "OpenClaw 联邦自动注册"
  echo "═══════════════════════════════════════════════════════════"
  echo ""

  log_info "收集节点信息..."
  local info
  info="$(gather_node_info)"
  local node_name ts_ip skills
  node_name="${info%%|*}"
  ts_ip="${info#*|}"; ts_ip="${ts_ip%%|*}"
  skills="${info##*|}"

  echo "节点名称: $node_name"
  echo "Tailscale IP: $ts_ip"
  echo "技能: $skills"
  echo ""

  if [[ -z "$master_ip" ]]; then
    master_ip=$(auto_discover_master || true)
  fi
  [[ -z "$master_ip" ]] && { log_error "未指定 Master IP"; exit 1; }
  log_info "Master IP: $master_ip"

  if [[ -z "$token" ]]; then
    token="$(read_token)"
    log_info "从文件读取 Token: $TOKEN_FILE"
  fi

  if register_to_master "$master_ip" "$token"; then
    save_config "$master_ip"
    log_success "注册流程完成！"
    echo ""
    log_info "配置文件已保存到: $CONFIG_FILE"
  else
    log_error "注册失败"
    exit 1
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "注册信息:"
  echo "═══════════════════════════════════════════════════════════"
  if need_cmd jq; then
    cat "$NODE_REG_FILE" | jq . || cat "$NODE_REG_FILE"
  else
    cat "$NODE_REG_FILE"
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

main "$@"
