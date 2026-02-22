#!/bin/bash
#
# OpenClaw 自动注册守护进程 (Master 端)
# 功能：自动批准 Worker 节点的连接请求
# 用法：./auto-register.sh [--watch]
#

set -e

# 颜色
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $(date +'%H:%M:%S') $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# 检查依赖
if ! command -v jq &> /dev/null; then
  echo "错误: 需要安装 jq"
  exit 1
fi

# 批准所有待处理请求
approve_all() {
  # 获取待处理列表 (JSON 格式)
  local pending_json
  pending_json=$(openclaw nodes pending --json 2>/dev/null || echo "[]")
  
  # 解析 Request ID
  local ids
  ids=$(echo "$pending_json" | jq -r '.[].requestId // empty')
  
  if [[ -z "$ids" ]]; then
    return 0
  fi
  
  echo "$pending_json" | jq -r '.[] | "收到连接请求: \(.name) (\(.os) \(.hostname))"'
  
  for id in $ids; do
    log "正在批准请求 ID: $id ..."
    if openclaw nodes approve "$id"; then
      success "已批准 Worker 加入联邦"
    else
      echo "批准失败: $id"
    fi
  done
}

# 单词运行模式
run_once() {
  log "检查待处理请求..."
  approve_all
  local count=$(openclaw nodes list --json | jq 'length')
  log "当前在线节点数: $count"
}

# 监控模式
watch_mode() {
  log "启动自动注册监控 (按 Ctrl+C 停止)..."
  while true; do
    approve_all
    sleep 5
  done
}

# 主入口
if [[ "$1" == "--watch" || "$1" == "-w" ]]; then
  watch_mode
else
  run_once
  echo ""
  echo "提示: 使用 --watch 参数可持续监控并自动批准新节点"
fi
