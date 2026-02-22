#!/bin/bash
#
# OpenClaw 联邦节点管理脚本
# 在主控节点上管理所有工作节点
#

set -e

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
DEFAULT_NODES_FILE="$OPENCLAW_HOME/.federation-nodes.json"
NODES_FILE="${NODES_FILE:-$DEFAULT_NODES_FILE}"

need_cmd() {
  local cmd=$1
  if ! command -v "$cmd" &>/dev/null; then
    error "缺少依赖命令: $cmd"
    return 1
  fi
  return 0
}

ensure_nodes_dir() {
  mkdir -p "$(dirname "$NODES_FILE")"
}

# 获取 Token（去除空白）
get_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    error "未找到 Token 文件: $TOKEN_FILE"
    exit 1
  fi
  local token
  token="$(cat "$TOKEN_FILE" | tr -d '[:space:]')"
  if [[ -z "$token" ]]; then
    error "Token 文件为空: $TOKEN_FILE"
    exit 1
  fi
  echo "$token"
}

# 添加节点
add_node() {
  local name=${1:-}
  local ip=${2:-}
  local skills=${3:-}

  if [[ -z "$name" || -z "$ip" ]]; then
    echo "用法: $0 add <节点名> <Tailscale-IP> [技能列表]"
    exit 1
  fi

  log "添加节点: $name ($ip)"

  local token
  token="$(get_token)"

  if ! openclaw pair approve \
    --name "$name" \
    --url "ws://$ip:18789" \
    --token "$token"; then
    error "节点 $name 添加失败"
    exit 1
  fi

  # 保存节点技能信息（可选）
  if [[ -n "$skills" ]]; then
    if ! need_cmd jq; then
      warn "未安装 jq，跳过写入节点技能信息"
    else
      ensure_nodes_dir
      local tmp
      tmp="$(mktemp)"
      if [[ -f "$NODES_FILE" ]]; then
        jq ". + {\"$name\": {\"ip\": \"$ip\", \"skills\": \"$skills\"}}" "$NODES_FILE" > "$tmp"
      else
        echo "{\"$name\": {\"ip\": \"$ip\", \"skills\": \"$skills\"}}" > "$tmp"
      fi
      mv "$tmp" "$NODES_FILE"
      chmod 600 "$NODES_FILE" 2>/dev/null || true
    fi
  fi

  success "节点 $name 添加完成"
}

# 列出所有节点
list_nodes() {
  echo -e "${BLUE}=== 联邦节点列表 ===${NC}"
  echo ""
  openclaw nodes list 2>/dev/null || echo "暂无节点"

  if [[ -f "$NODES_FILE" ]]; then
    echo ""
    echo -e "${BLUE}节点技能信息:${NC}"
    if need_cmd jq; then
      jq -r 'to_entries[] | "  \(.key): \(.value.skills // "无")"' "$NODES_FILE" || cat "$NODES_FILE"
    else
      cat "$NODES_FILE"
    fi
  fi
}

# 检查节点状态
status() {
  log "检查所有节点状态..."
  openclaw nodes status
}

# 在指定节点执行命令
exec_on() {
  local node=${1:-}
  shift || true
  local cmd="$*"

  if [[ -z "$node" || -z "$cmd" ]]; then
    echo "用法: $0 exec <节点名> <命令>"
    echo "示例: $0 exec home-server docker ps"
    exit 1
  fi

  log "在 $node 上执行: $cmd"
  openclaw nodes invoke "$node" -- $cmd
}

# 广播命令到所有节点
broadcast() {
  local cmd="$*"

  if [[ -z "$cmd" ]]; then
    echo "用法: $0 broadcast <命令>"
    exit 1
  fi

  if ! need_cmd jq; then
    error "broadcast 需要 jq（用于解析节点列表）"
    exit 1
  fi

  log "广播命令到所有节点: $cmd"

  # 获取所有节点名
  local nodes
  nodes=$(openclaw nodes list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)

  if [[ -z "$nodes" ]]; then
    warn "没有找到节点"
    exit 1
  fi

  for node in $nodes; do
    echo ""
    echo -e "${BLUE}[$node]${NC}"
    openclaw nodes invoke "$node" -- $cmd 2>&1 || error "$node 执行失败"
  done
}

# 根据技能查找节点
find_by_skill() {
  local skill=${1:-}

  if [[ -z "$skill" ]]; then
    echo "用法: $0 find <技能名>"
    exit 1
  fi

  if [[ ! -f "$NODES_FILE" ]]; then
    warn "没有节点技能记录（文件不存在: $NODES_FILE）"
    exit 1
  fi

  if ! need_cmd jq; then
    error "find 需要 jq"
    exit 1
  fi

  log "查找具有 '$skill' 技能的节点..."
  jq -r --arg s "$skill" '
    to_entries[]
    | select(.value.skills | contains($s))
    | "  \(.key) (\(.value.ip))"
  ' "$NODES_FILE"
}

# 显示帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦节点管理器

用法: ./manage-federation.sh <命令> [参数]

环境变量:
  OPENCLAW_HOME  OpenClaw 目录（默认: ~/.openclaw 或 sudo 用户家目录）
  TOKEN_FILE     Token 文件路径（默认: $OPENCLAW_HOME/.federation-token）
  NODES_FILE     节点记录文件路径（默认: $OPENCLAW_HOME/.federation-nodes.json）

命令:
  add <名称> <IP> [技能]    添加新节点
                            例: ./manage-federation.sh add home-server 100.64.0.2 "docker k8s"

  list                      列出所有节点
  status                    检查节点状态

  exec <节点> <命令>        在指定节点执行命令
                            例: ./manage-federation.sh exec home-server docker ps

  broadcast <命令>          广播命令到所有节点（需要 jq）
                            例: ./manage-federation.sh broadcast uname -a

  find <技能>               查找具有指定技能的节点（需要 jq）
                            例: ./manage-federation.sh find docker

EOF
}

# 主入口
case "${1:-}" in
  add)
    shift
    add_node "$@"
    ;;
  list|ls)
    list_nodes
    ;;
  status|st)
    status
    ;;
  exec|run)
    shift
    exec_on "$@"
    ;;
  broadcast|all)
    shift
    broadcast "$@"
    ;;
  find|search)
    shift
    find_by_skill "$@"
    ;;
  help|--help|-h|"")
    show_help
    ;;
  *)
    error "未知命令: $1"
    show_help
    exit 1
    ;;
esac
