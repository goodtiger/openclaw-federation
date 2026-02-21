#!/bin/bash
#
# OpenClaw 联邦节点管理脚本
# 在主控节点上管理所有工作节点
#

TOKEN_FILE="/root/.openclaw/.federation-token"
NODES_FILE="/root/.openclaw/.federation-nodes.json"

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

# 获取 Token
get_token() {
  if [[ -f "$TOKEN_FILE" ]]; then
    cat "$TOKEN_FILE"
  else
    error "未找到 Token 文件"
    exit 1
  fi
}

# 添加节点
add_node() {
  local name=$1
  local ip=$2
  local skills=$3
  
  if [[ -z "$name" || -z "$ip" ]]; then
    echo "用法: $0 add <节点名> <Tailscale-IP> [技能列表]"
    exit 1
  fi
  
  log "添加节点: $name ($ip)"
  
  TOKEN=$(get_token)
  
  openclaw pair approve \
    --name "$name" \
    --url "ws://$ip:18789" \
    --token "$TOKEN"
  
  # 保存节点信息
  if [[ -n "$skills" ]]; then
    local tmp=$(mktemp)
    if [[ -f "$NODES_FILE" ]]; then
      jq ". + {\"$name\": {\"ip\": \"$ip\", \"skills\": \"$skills\"}}" "$NODES_FILE" > "$tmp"
    else
      echo "{\"$name\": {\"ip\": \"$ip\", \"skills\": \"$skills\"}}" > "$tmp"
    fi
    mv "$tmp" "$NODES_FILE"
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
    cat "$NODES_FILE" | jq -r 'to_entries[] | "  \(.key): \(.value.skills // "无")"'
  fi
}

# 检查节点状态
status() {
  log "检查所有节点状态..."
  openclaw nodes status
}

# 在指定节点执行命令
exec_on() {
  local node=$1
  shift
  local cmd="$@"
  
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
  local cmd="$@"
  
  if [[ -z "$cmd" ]]; then
    echo "用法: $0 broadcast <命令>"
    exit 1
  fi
  
  log "广播命令到所有节点: $cmd"
  
  # 获取所有节点名
  nodes=$(openclaw nodes list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null)
  
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
  local skill=$1
  
  if [[ -z "$skill" ]]; then
    echo "用法: $0 find <技能名>"
    exit 1
  fi
  
  if [[ ! -f "$NODES_FILE" ]]; then
    warn "没有节点技能记录"
    exit 1
  fi
  
  log "查找具有 '$skill' 技能的节点..."
  cat "$NODES_FILE" | jq -r --arg s "$skill" '
    to_entries[] 
    | select(.value.skills | contains($s)) 
    | "  \(.key) (\(.value.ip))"
  '
}

# 显示帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦节点管理器

用法: ./manage-federation.sh <命令> [参数]

命令:
  add <名称> <IP> [技能]    添加新节点
                            例: ./manage-federation.sh add home-server 100.64.0.2 "docker k8s"
  
  list                      列出所有节点
  status                    检查节点状态
  
  exec <节点> <命令>        在指定节点执行命令
                            例: ./manage-federation.sh exec home-server docker ps
  
  broadcast <命令>          广播命令到所有节点
                            例: ./manage-federation.sh broadcast uname -a
  
  find <技能>               查找具有指定技能的节点
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
