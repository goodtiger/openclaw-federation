#!/bin/bash
#
# OpenClaw 联邦节点管理脚本 (修复版)
# 用于 Master 节点管理 Worker
#

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查 OpenClaw 是否运行
check_gateway() {
  if ! openclaw gateway status &> /dev/null; then
    error "Gateway 未运行，请先启动 Master 节点"
  fi
}

# 列出所有节点
list_nodes() {
  echo -e "${BLUE}=== 联邦节点列表 ===${NC}"
  openclaw nodes list
}

# 查看待处理请求
list_pending() {
  echo -e "${BLUE}=== 待批准请求 ===${NC}"
  openclaw nodes pending
  echo ""
  echo "提示: 使用 '$0 approve <ID>' 批准节点"
}

# 批准节点
approve_node() {
  local id=$1
  if [[ -z "$id" ]]; then
    list_pending
    exit 1
  fi
  
  log "正在批准请求: $id"
  openclaw nodes approve "$id"
}

# 在指定节点执行命令
exec_on() {
  local node=$1
  shift
  local cmd="$@"
  
  if [[ -z "$node" || -z "$cmd" ]]; then
    echo "用法: $0 exec <节点名|ID> <命令>"
    echo "示例: $0 exec home-server docker ps"
    exit 1
  fi
  
  log "在 [$node] 上执行: $cmd"
  openclaw nodes invoke "$node" -- "$cmd"
}

# 广播命令到所有节点
broadcast() {
  local cmd="$@"
  
  if [[ -z "$cmd" ]]; then
    echo "用法: $0 broadcast <命令>"
    exit 1
  fi
  
  log "广播命令到所有在线节点: $cmd"
  
  # 获取所有节点名 (JSON解析需要jq)
  if ! command -v jq &> /dev/null; then
    error "广播功能需要安装 jq"
  fi
  
  local nodes
  nodes=$(openclaw nodes list --json 2>/dev/null | jq -r '.[].id')
  
  if [[ -z "$nodes" ]]; then
    echo "没有在线节点"
    exit 0
  fi
  
  for node in $nodes; do
    echo "--------------------------------"
    echo -e "节点: ${GREEN}$node${NC}"
    openclaw nodes invoke "$node" -- "$cmd" || echo "执行失败"
  done
  echo "--------------------------------"
}

# 显示帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦管理器 (Master)

用法: ./manage-federation.sh <命令> [参数]

核心流程:
  1. Worker 运行 connect 命令连接 Master
  2. Master 运行 pending 查看请求
  3. Master 运行 approve 批准请求

命令:
  list                      列出已连接节点
  pending                   查看待批准的 Worker 请求
  approve <ID>              批准 Worker 加入 (ID 来自 pending 命令)
  exec <节点> <命令>        在指定节点执行命令
  broadcast <命令>          在所有节点执行命令
  status                    检查 Gateway 状态

EOF
}

# 主入口
case "${1:-}" in
  help|--help|-h|"")
    show_help
    exit 0
    ;;
esac

check_gateway

case "${1:-}" in
  list|ls)
    list_nodes
    ;;
  pending|req)
    list_pending
    ;;
  approve|accept)
    shift
    approve_node "$@"
    ;;
  exec|run)
    shift
    exec_on "$@"
    ;;
  broadcast|all)
    shift
    broadcast "$@"
    ;;
  status)
    openclaw gateway status
    ;;
  *)
    error "未知命令: $1\n请运行 '$0 help' 查看帮助"
    ;;
esac
