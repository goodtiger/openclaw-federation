#!/bin/bash
#
# OpenClaw 联邦健康检查脚本
# 在 Master 节点上运行，定期检查所有 Worker 节点状态
#

set -e

# 配置
CONFIG_FILE="/root/.openclaw/.federation-health.conf"
LOG_FILE="/var/log/openclaw-health.log"
STATUS_FILE="/root/.openclaw/.federation-status.json"
ALERT_WEBHOOK=""  # 可选：告警 Webhook URL

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# 初始化日志目录
init() {
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "$(dirname "$STATUS_FILE")"
  
  # 创建默认配置
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" << 'EOF'
# OpenClaw 健康检查配置

# 检查间隔（秒）
CHECK_INTERVAL=60

# 超时时间（秒）
TIMEOUT=5

# 连续失败几次后标记为不健康
FAIL_THRESHOLD=3

# 是否启用自动移除不健康节点
AUTO_REMOVE_UNHEALTHY=false

# 告警 webhook（可选）
# ALERT_WEBHOOK="https://hooks.slack.com/services/xxx"
EOF
    chmod 600 "$CONFIG_FILE"
  fi
  
  # 加载配置
  source "$CONFIG_FILE"
}

# 加载配置
check_node_health() {
  local node_name=$1
  local node_url=$2
  local token=$3
  
  # 使用 curl 测试连通性
  local response
  local http_code
  
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout "$TIMEOUT" \
    --max-time "$TIMEOUT" \
    -H "Authorization: Bearer $token" \
    "${node_url/websocket/http}/health" 2>/dev/null || echo "000")
  
  if [[ "$response" == "200" ]]; then
    echo "healthy"
  else
    echo "unhealthy:$response"
  fi
}

# 检查所有节点
health_check_all() {
  log_info "$(date '+%Y-%m-%d %H:%M:%S') 开始健康检查..."
  
  # 获取所有节点列表
  local nodes_json
  nodes_json=$(openclaw nodes list --json 2>/dev/null || echo "[]")
  
  if [[ -z "$nodes_json" || "$nodes_json" == "[]" ]]; then
    log_warn "没有注册任何节点"
    return 0
  fi
  
  # 获取 Token
  local token
  token=$(cat /root/.openclaw/.federation-token 2>/dev/null || echo "")
  
  if [[ -z "$token" ]]; then
    log_error "无法读取 Token"
    return 1
  fi
  
  # 检查结果数组
  local results=()
  local healthy_count=0
  local unhealthy_count=0
  
  # 遍历检查每个节点
  while IFS= read -r node; do
    local name=$(echo "$node" | jq -r '.name')
    local url=$(echo "$node" | jq -r '.url')
    local status=$(echo "$node" | jq -r '.status')
    
    [[ -z "$name" || "$name" == "null" ]] && continue
    
    log_info "检查节点: $name ($url)"
    
    local health_result
    health_result=$(check_node_health "$name" "$url" "$token")
    
    if [[ "$health_result" == "healthy" ]]; then
      log_success "  $name: 健康"
      ((healthy_count++))
      results+=("{\"name\":\"$name\",\"status\":\"healthy\",\"timestamp\":\"$(date -Iseconds)\"}")
    else
      local error_code="${health_result#unhealthy:}"
      log_error "  $name: 不健康 (HTTP $error_code)"
      ((unhealthy_count++))
      results+=("{\"name\":\"$name\",\"status\":\"unhealthy\",\"error\":\"$error_code\",\"timestamp\":\"$(date -Iseconds)\"}")
      
      # 发送告警
      send_alert "$name" "$error_code"
      
      # 自动移除（如果启用）
      if [[ "$AUTO_REMOVE_UNHEALTHY" == "true" ]]; then
        log_warn "  自动移除不健康节点: $name"
        openclaw nodes remove "$name" 2>/dev/null || true
      fi
    fi
  done < <(echo "$nodes_json" | jq -c '.[]')
  
  # 保存状态
  local status_json
  status_json=$(printf '[%s]' "$(IFS=,; echo "${results[*]}")")
  echo "{\"timestamp\":\"$(date -Iseconds)\",\"total\":$((healthy_count + unhealthy_count)),\"healthy\":$healthy_count,\"unhealthy\":$unhealthy_count,\"nodes\":$status_json}" > "$STATUS_FILE"
  
  log_info "检查完成: $healthy_count 健康, $unhealthy_count 不健康"
  echo ""
}

# 发送告警
send_alert() {
  local node_name=$1
  local error_code=$2
  
  [[ -z "$ALERT_WEBHOOK" ]] && return 0
  
  local message="⚠️ OpenClaw 联邦节点告警\n节点: $node_name\n错误: HTTP $error_code\n时间: $(date '+%Y-%m-%d %H:%M:%S')"
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"$message\"}" \
    "$ALERT_WEBHOOK" > /dev/null 2>&1 || true
}

# 显示状态
show_status() {
  if [[ ! -f "$STATUS_FILE" ]]; then
    echo "暂无状态信息"
    return 0
  fi
  
  echo "═══════════════════════════════════════════════════════════"
  echo "OpenClaw 联邦节点健康状态"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  cat "$STATUS_FILE" | jq -r '
    "检查时间: \(.timestamp)",
    "节点总数: \(.total)",
    "健康: \(.healthy)",
    "不健康: \(.unhealthy)",
    "",
    "节点详情:",
    (.nodes[] | "  \(.name): \(.status) \(.error // "")")
  '
  
  echo ""
}

# 守护进程模式
run_daemon() {
  log_info "启动健康检查守护进程 (PID: $$)"
  log_info "检查间隔: ${CHECK_INTERVAL}s"
  
  while true; do
    health_check_all
    sleep "$CHECK_INTERVAL"
  done
}

# 安装为系统服务
install_service() {
  log_info "安装为 systemd 服务..."
  
  local service_file="/etc/systemd/system/openclaw-health.service"
  
  cat > "$service_file" << EOF
[Unit]
Description=OpenClaw Federation Health Check
After=network.target

[Service]
Type=simple
ExecStart=/root/.openclaw/workspace/health-check.sh daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable openclaw-health
  systemctl start openclaw-health
  
  log_success "服务已安装并启动"
  log_info "查看状态: systemctl status openclaw-health"
  log_info "查看日志: journalctl -u openclaw-health -f"
}

# 帮助
show_help() {
  cat << 'EOF'
OpenClaw 联邦健康检查工具

用法:
  health-check.sh [命令] [选项]

命令:
  check          执行一次健康检查
  daemon         以守护进程模式运行
  status         显示当前状态
  install        安装为 systemd 服务
  logs           查看日志

示例:
  # 手动执行一次检查
  ./health-check.sh check

  # 启动守护进程
  ./health-check.sh daemon

  # 查看状态
  ./health-check.sh status

  # 安装为系统服务（推荐）
  ./health-check.sh install

配置:
  编辑 /root/.openclaw/.federation-health.conf 修改检查参数

EOF
}

# 主入口
case "${1:-check}" in
  check|once)
    init
    health_check_all
    ;;
  daemon|run)
    init
    run_daemon
    ;;
  status|s)
    show_status
    ;;
  install|setup)
    init
    install_service
    ;;
  logs|log)
    tail -f "$LOG_FILE"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "未知命令: $1"
    show_help
    exit 1
    ;;
esac
