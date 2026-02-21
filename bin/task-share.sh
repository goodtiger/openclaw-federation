#!/bin/bash
#
# OpenClaw 联邦任务共享系统
# 基于文件的轻量级任务协作
#

set -e

# 配置
SHARED_DIR="${SHARED_DIR:-/root/.openclaw/shared}"
TASKS_DIR="$SHARED_DIR/tasks"
QUEUE_DIR="$TASKS_DIR/queue"
ACTIVE_DIR="$TASKS_DIR/active"
DONE_DIR="$TASKS_DIR/done"
ARCHIVE_DIR="$TASKS_DIR/archive"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_highlight() { echo -e "${CYAN}$1${NC}"; }

now_iso() {
  if date -Iseconds >/dev/null 2>&1; then
    date -Iseconds
  else
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

date_days_ago() {
  local days=$1
  if [[ -z "$days" || ! "$days" =~ ^[0-9]+$ ]]; then
    days=7
  fi
  if date -d "$days days ago" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "$days days ago" +%Y-%m-%d
  else
    date -v -"${days}"d +%Y-%m-%d
  fi
}

# 初始化任务系统
init() {
  mkdir -p "$QUEUE_DIR" "$ACTIVE_DIR" "$DONE_DIR" "$ARCHIVE_DIR"
  
  # 创建任务索引文件
  if [[ ! -f "$TASKS_DIR/index.json" ]]; then
    echo '{"tasks": [], "last_update": "'$(now_iso)'"}' > "$TASKS_DIR/index.json"
  fi
  
  log_success "任务共享系统初始化完成"
  log_info "任务目录: $TASKS_DIR"
}

# 生成任务 ID
generate_task_id() {
  echo "task-$(date +%Y%m%d)-$(openssl rand -hex 4)"
}

# 创建任务
create_task() {
  local title="${1:-}"
  local assignee="${2:-any}"
  local priority="${3:-normal}"
  local description="${4:-}"
  local from_node="${5:-$(hostname -s)}"
  
  if [[ -z "$title" ]]; then
    log_error "请提供任务标题"
    echo "用法: $0 create \"任务标题\" [assignee] [priority] [description]"
    return 1
  fi
  
  local task_id=$(generate_task_id)
  local task_file="$QUEUE_DIR/$task_id.json"
  
  cat > "$task_file" << EOF
{
  "id": "$task_id",
  "title": "$title",
  "description": "$description",
  "status": "pending",
  "priority": "$priority",
  "assignee": "$assignee",
  "from": "$from_node",
  "created_at": "$(now_iso)",
  "updated_at": "$(now_iso)",
  "started_at": null,
  "completed_at": null,
  "result": null,
  "progress": 0,
  "logs": []
}
EOF
  
  update_index
  log_success "任务创建成功: $task_id"
  echo "$task_file"
}

# 领取任务（Worker 调用）
claim_task() {
  local node_name="${1:-$(hostname -s)}"
  local priority_filter="${2:-}"
  
  # 查找可领取的任务
  local task_file
  if [[ -n "$priority_filter" ]]; then
    task_file=$(find "$QUEUE_DIR" -name "*.json" -type f | while read f; do
      if [[ "$(jq -r '.priority' "$f")" == "$priority_filter" ]]; then
        echo "$f"
        break
      fi
    done)
  else
    # 优先找高优先级
    task_file=$(find "$QUEUE_DIR" -name "*.json" -type f | while read f; do
      if [[ "$(jq -r '.priority' "$f")" == "high" ]]; then
        echo "$f"
        break
      fi
    done)
    
    # 没有高优先级则找任意
    if [[ -z "$task_file" ]]; then
      task_file=$(find "$QUEUE_DIR" -name "*.json" -type f | head -1)
    fi
  fi
  
  if [[ -z "$task_file" || ! -f "$task_file" ]]; then
    log_warn "没有待处理的任务"
    return 1
  fi
  
  local task_id=$(basename "$task_file" .json)
  local active_file="$ACTIVE_DIR/$task_id.json"

  # 原子领取：先移动到 active，避免并发重复领取
  if ! mv "$task_file" "$active_file" 2>/dev/null; then
    log_warn "任务已被领取，请重试"
    return 1
  fi

  # 更新任务状态
  if ! jq --arg node "$node_name" --arg time "$(now_iso)" \
     '.status = "active" | 
      .assignee = $node | 
      .started_at = $time | 
      .updated_at = $time |
      .logs += [{"time": $time, "message": "任务被 " + $node + " 领取"}]' \
     "$active_file" > "${active_file}.tmp"; then
    log_error "更新任务状态失败"
    mv "$active_file" "$task_file" 2>/dev/null || true
    return 1
  fi

  mv "${active_file}.tmp" "$active_file"
  update_index
  
  log_success "任务已领取: $task_id"
  echo "$active_file"
}

# 更新任务进度
update_progress() {
  local task_id="${1:-}"
  local progress="${2:-}"
  local message="${3:-}"
  local node_name="${4:-$(hostname -s)}"
  
  if [[ -z "$task_id" || -z "$progress" ]]; then
    log_error "请提供任务 ID 和进度"
    return 1
  fi
  
  local task_file="$ACTIVE_DIR/$task_id.json"
  if [[ ! -f "$task_file" ]]; then
    # 可能在 queue 中
    task_file="$QUEUE_DIR/$task_id.json"
    if [[ ! -f "$task_file" ]]; then
      log_error "任务不存在或已完成: $task_id"
      return 1
    fi
  fi
  
  jq --arg prog "$progress" --arg msg "$message" --arg node "$node_name" --arg time "$(now_iso)" \
     '.progress = ($prog | tonumber) | 
      .updated_at = $time |
      .logs += [{"time": $time, "node": $node, "progress": ($prog | tonumber), "message": $msg}]' \
     "$task_file" > "${task_file}.tmp"
  mv "${task_file}.tmp" "$task_file"
  
  update_index
  log_success "进度更新: $task_id - $progress%"
}

# 完成任务
complete_task() {
  local task_id="${1:-}"
  local result="${2:-}"
  local status="${3:-completed}"
  local node_name="${4:-$(hostname -s)}"
  
  if [[ -z "$task_id" ]]; then
    log_error "请提供任务 ID"
    return 1
  fi
  
  local active_file="$ACTIVE_DIR/$task_id.json"
  if [[ ! -f "$active_file" ]]; then
    log_error "任务不存在或不在活动中: $task_id"
    return 1
  fi
  
  local done_file="$DONE_DIR/$task_id.json"
  
  jq --arg result "$result" --arg status "$status" --arg node "$node_name" --arg time "$(now_iso)" \
     '.status = $status | 
      .result = $result |
      .completed_at = $time |
      .updated_at = $time |
      .progress = 100 |
      .logs += [{"time": $time, "node": $node, "message": "任务完成: " + $status}]' \
     "$active_file" > "$done_file"
  
  rm "$active_file"
  update_index
  
  log_success "任务完成: $task_id ($status)"
  echo "$done_file"
}

# 列出任务
list_tasks() {
  local status_filter="${1:-all}"
  local format="${2:-table}"
  
  case "$status_filter" in
    pending|queue)
      list_dir="$QUEUE_DIR"
      ;;
    active|running)
      list_dir="$ACTIVE_DIR"
      ;;
    done|completed)
      list_dir="$DONE_DIR"
      ;;
    all|*)
      list_dir="$TASKS_DIR"
      ;;
  esac
  
  if [[ "$format" == "json" ]]; then
    # JSON 格式输出
    echo "["
    local first=true
    find "$list_dir" -name "*.json" -type f | while read f; do
      [[ "$first" == "true" ]] && first=false || echo ","
      cat "$f"
    done
    echo "]"
  else
    # 表格格式输出
    echo ""
    log_highlight "=== 任务列表 ($status_filter) ==="
    echo ""
    printf "%-20s %-30s %-10s %-10s %-10s\n" "ID" "标题" "状态" "优先级" "负责人"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    for dir in "$QUEUE_DIR" "$ACTIVE_DIR" "$DONE_DIR"; do
      [[ -d "$dir" ]] || continue
      for f in "$dir"/*.json; do
        [[ -f "$f" ]] || continue
        local id=$(jq -r '.id' "$f")
        local title=$(jq -r '.title' "$f")
        local status=$(jq -r '.status' "$f")
        local priority=$(jq -r '.priority' "$f")
        local assignee=$(jq -r '.assignee' "$f")
        printf "%-20s %-30s %-10s %-10s %-10s\n" "${id:0:20}" "${title:0:30}" "$status" "$priority" "$assignee"
      done
    done
    echo ""
  fi
}

# 查看任务详情
show_task() {
  local task_id="${1:-}"
  
  if [[ -z "$task_id" ]]; then
    log_error "请提供任务 ID"
    return 1
  fi
  
  # 查找任务文件
  local task_file
  for dir in "$QUEUE_DIR" "$ACTIVE_DIR" "$DONE_DIR"; do
    if [[ -f "$dir/$task_id.json" ]]; then
      task_file="$dir/$task_id.json"
      break
    fi
  done
  
  if [[ -z "$task_file" ]]; then
    log_error "任务不存在: $task_id"
    return 1
  fi
  
  echo ""
  log_highlight "=== 任务详情 ==="
  echo ""
  jq '.' "$task_file"
  echo ""
}

# 更新索引
update_index() {
  local index_file="$TASKS_DIR/index.json"
  
  # 收集所有任务
  local tasks='[]'
  for dir in "$QUEUE_DIR" "$ACTIVE_DIR" "$DONE_DIR"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.json; do
      [[ -f "$f" ]] || continue
      local task_info=$(jq '{id, title, status, priority, assignee, progress, updated_at}' "$f")
      tasks=$(echo "$tasks" | jq --argjson task "$task_info" '. + [$task]')
    done
  done
  
  # 更新索引
  echo "{\"tasks\": $tasks, \"last_update\": \"$(now_iso)\"}" | jq '.' > "$index_file"
}

# 获取统计信息
stats() {
  local pending=$(find "$QUEUE_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
  local active=$(find "$ACTIVE_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
  local done=$(find "$DONE_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
  
  echo ""
  log_highlight "=== 任务统计 ==="
  echo ""
  echo "  待处理 (pending):  $pending"
  echo "  进行中 (active):   $active"
  echo "  已完成 (done):     $done"
  echo "  ─────────────────────────"
  echo "  总计:              $((pending + active + done))"
  echo ""
}

# 清理旧任务
cleanup() {
  local days="${1:-7}"
  local before_date
  before_date=$(date_days_ago "$days")
  
  log_info "清理 $days 天前的已完成任务..."
  
  find "$DONE_DIR" -name "*.json" -type f | while read f; do
    local completed=$(jq -r '.completed_at' "$f")
    if [[ "$completed" < "$before_date" ]]; then
      mv "$f" "$ARCHIVE_DIR/"
      log_info "归档: $(basename "$f")"
    fi
  done
  
  update_index
  log_success "清理完成"
}

# 帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦任务共享系统

用法:
  task-share.sh [命令] [选项]

命令:
  init                    初始化任务系统
  create TITLE [ASSIGNEE] [PRIORITY] [DESC]
                         创建新任务
  claim [NODE] [PRIORITY]
                         领取任务（Worker 调用）
  update ID PROGRESS [MSG] [NODE]
                         更新任务进度
  complete ID [RESULT] [STATUS] [NODE]
                         完成任务
  list [status] [format]  列出任务（status: pending/active/done/all）
  show ID                 查看任务详情
  stats                   显示统计信息
  cleanup [DAYS]          清理旧任务（默认7天）
  help                    显示帮助

示例:
  # Master 创建任务
  task-share.sh create "部署 Nginx" worker1 high "在 worker1 上部署 nginx"

  # Worker 领取任务
  task-share.sh claim worker1

  # Worker 更新进度
  task-share.sh update task-20260221-abc123 50 "正在拉取镜像..."

  # Worker 完成任务
  task-share.sh complete task-20260221-abc123 "部署成功，访问 http://worker1:80"

  # 查看所有任务
  task-share.sh list

环境变量:
  SHARED_DIR              共享目录路径（默认: /root/.openclaw/shared）

EOF
}

# 主入口
case "${1:-help}" in
  init|setup)
    init
    ;;
  create|new)
    shift
    create_task "$@"
    ;;
  claim|take)
    shift
    claim_task "$@"
    ;;
  update|progress)
    shift
    update_progress "$@"
    ;;
  complete|finish|done)
    shift
    complete_task "$@"
    ;;
  list|ls)
    shift
    list_tasks "$@"
    ;;
  show|view|cat)
    shift
    show_task "$@"
    ;;
  stats|stat|count)
    stats
    ;;
  cleanup|archive)
    shift
    cleanup "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "未知命令: $1"
    show_help
    exit 1
    ;;
esac
