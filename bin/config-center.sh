#!/bin/bash
#
# OpenClaw 联邦配置中心
# Master 节点作为配置源，Worker 节点定期同步
#

set -e

# 配置
ROLE="${1:-}"
CONFIG_DIR="/root/.openclaw/.federation-config"
MASTER_CONFIG="$CONFIG_DIR/master-config.json"
SYNC_INTERVAL="${SYNC_INTERVAL:-300}"  # 默认5分钟同步一次

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

# 初始化配置目录
init_config_center() {
  mkdir -p "$CONFIG_DIR"
  
  # 创建默认主配置
  if [[ ! -f "$MASTER_CONFIG" ]]; then
    cat > "$MASTER_CONFIG" << 'EOF'
{
  "version": 1,
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist"
    }
  },
  "agents": {
    "defaults": {
      "compaction": {
        "mode": "safeguard"
      }
    }
  },
  "federation": {
    "auto_sync": true,
    "sync_interval": 300
  },
  "updated_at": ""
}
EOF
    log_success "创建默认配置文件: $MASTER_CONFIG"
  fi
}

# ═══════════════════════════════════════════════════════════
# Master 端功能
# ═══════════════════════════════════════════════════════════

# Master: 启动配置服务
master_start_service() {
  log_info "启动配置中心服务 (Master)..."
  
  # 检查是否以 root 运行
  if [[ $EUID -ne 0 ]]; then
    log_error "请以 root 权限运行"
    exit 1
  fi
  
  init_config_center
  
  # 创建配置服务的 API 端点
  # 这里我们创建一个简单的 HTTP 服务，实际使用时可以集成到 Gateway
  
  log_success "配置中心已准备"
  log_info "配置文件位置: $MASTER_CONFIG"
  log_info ""
  log_info "配置服务 API:"
  log_info "  GET  /config           - 获取完整配置"
  log_info "  GET  /config/channels  - 获取通道配置"
  log_info "  POST /config/sync      - 触发同步"
  log_info ""
  log_info "Worker 节点可以通过以下命令同步配置:"
  log_info "  config-center.sh sync"
}

# Master: 更新配置
master_update_config() {
  local key=$1
  local value=$2
  
  log_info "更新配置: $key = $value"
  
  # 更新配置并更新时间戳
  local tmp_file=$(mktemp)
  jq --arg key "$key" --arg value "$value" \
     '.[$key] = $value | .updated_at = now' \
     "$MASTER_CONFIG" > "$tmp_file"
  mv "$tmp_file" "$MASTER_CONFIG"
  
  log_success "配置已更新"
  
  # 触发同步通知（可选）
  notify_workers_sync
}

# Master: 通知 Worker 同步
notify_workers_sync() {
  log_info "通知所有 Worker 节点同步配置..."
  
  # 获取所有节点
  local nodes
  nodes=$(openclaw nodes list --json 2>/dev/null || echo "[]")
  
  # 向每个节点发送同步通知
  while IFS= read -r node; do
    local name=$(echo "$node" | jq -r '.name')
    local url=$(echo "$node" | jq -r '.url')
    
    [[ -z "$name" || "$name" == "null" ]] && continue
    
    # 异步发送通知（不等待响应）
    (
      curl -s -X POST \
        --connect-timeout 3 \
        --max-time 3 \
        "${url/websocket/http}/api/config/notify" \
        > /dev/null 2>&1 || true
    ) &
  done < <(echo "$nodes" | jq -c '.[]')
  
  log_success "同步通知已发送"
}

# Master: 导出配置给 Worker
master_export_config() {
  local format=${1:-full}  # full, minimal, channels
  
  case "$format" in
    full)
      cat "$MASTER_CONFIG"
      ;;
    minimal)
      jq '{channels, agents}' "$MASTER_CONFIG"
      ;;
    channels)
      jq '.channels' "$MASTER_CONFIG"
      ;;
    *)
      cat "$MASTER_CONFIG"
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════
# Worker 端功能
# ═══════════════════════════════════════════════════════════

# Worker: 从 Master 同步配置
worker_sync_config() {
  log_info "从 Master 同步配置..."
  
  # 读取 Master IP
  local master_ip
  if [[ -f "/root/.openclaw/.federation-config.json" ]]; then
    master_ip=$(jq -r '.master_ip' "/root/.openclaw/.federation-config.json" 2>/dev/null)
  fi
  
  if [[ -z "$master_ip" || "$master_ip" == "null" ]]; then
    log_error "未找到 Master IP，请先运行 auto-register.sh"
    exit 1
  fi
  
  # 读取 Token
  local token
  token=$(cat /root/.openclaw/.federation-token 2>/dev/null || echo "")
  
  if [[ -z "$token" ]]; then
    log_error "未找到 Token"
    exit 1
  fi
  
  # 拉取配置
  log_info "从 http://${master_ip}:18789 拉取配置..."
  
  local remote_config
  remote_config=$(curl -s \
    --connect-timeout 10 \
    --max-time 10 \
    -H "Authorization: Bearer $token" \
    "http://${master_ip}:18789/api/config" 2>/dev/null)
  
  if [[ -z "$remote_config" ]]; then
    log_error "无法从 Master 获取配置"
    exit 1
  fi
  
  # 保存远程配置
  echo "$remote_config" > "$CONFIG_DIR/remote-config.json"
  
  # 合并配置到本地
  merge_remote_config "$remote_config"
  
  log_success "配置同步完成"
}

# Worker: 合并远程配置
merge_remote_config() {
  local remote_config=$1
  
  log_info "合并远程配置..."
  
  local local_config="/root/.openclaw/openclaw.json"
  
  if [[ ! -f "$local_config" ]]; then
    log_error "本地配置文件不存在"
    return 1
  fi
  
  # 备份本地配置
  cp "$local_config" "$local_config.backup.$(date +%Y%m%d_%H%M%S)"
  
  # 提取需要同步的字段
  local channels=$(echo "$remote_config" | jq '.channels // empty')
  local agents=$(echo "$remote_config" | jq '.agents // empty')
  
  # 合并到本地配置
  local tmp_file=$(mktemp)
  jq --argjson channels "$channels" --argjson agents "$agents" \
     '.channels = $channels | .agents = $agents | .meta.config_synced_at = now' \
     "$local_config" > "$tmp_file"
  mv "$tmp_file" "$local_config"
  
  log_success "配置已合并"
}

# Worker: 启动自动同步守护进程
worker_start_sync_daemon() {
  log_info "启动配置自动同步守护进程..."
  log_info "同步间隔: ${SYNC_INTERVAL}秒"
  
  while true; do
    worker_sync_config || log_warn "同步失败，将在下次重试"
    sleep "$SYNC_INTERVAL"
  done
}

# Worker: 查看配置差异
worker_diff_config() {
  log_info "比较本地和远程配置..."
  
  local local_config="/root/.openclaw/openclaw.json"
  
  if [[ ! -f "$CONFIG_DIR/remote-config.json" ]]; then
    log_warn "没有远程配置缓存，请先执行同步"
    return 1
  fi
  
  echo ""
  echo "配置差异:"
  diff -u <(jq -S . "$CONFIG_DIR/remote-config.json") \
          <(jq -S . "$local_config") || true
}

# ═══════════════════════════════════════════════════════════
# 帮助和主入口
# ═══════════════════════════════════════════════════════════

show_help() {
  cat << 'EOF'
OpenClaw 联邦配置中心

用法:
  config-center.sh [角色] [命令] [选项]

角色:
  master    作为配置中心（在 Master 节点上运行）
  worker    作为配置消费者（在 Worker 节点上运行）

Master 命令:
  start         启动配置服务
  update KEY VALUE  更新配置项
  export        导出配置

Worker 命令:
  sync          手动同步配置
  daemon        启动自动同步守护进程
  diff          查看配置差异

示例:
  # Master 启动配置服务
  ./config-center.sh master start

  # Master 更新配置
  ./config-center.sh master update channels.telegram.enabled true

  # Worker 手动同步
  ./config-center.sh worker sync

  # Worker 启动自动同步
  ./config-center.sh worker daemon

环境变量:
  SYNC_INTERVAL    自动同步间隔（秒，默认 300）

EOF
}

# 主入口
main() {
  case "${ROLE:-}" in
    master)
      case "${2:-start}" in
        start|init)
          master_start_service
          ;;
        update|set)
          master_update_config "$3" "$4"
          ;;
        export)
          master_export_config "$3"
          ;;
        *)
          echo "未知 Master 命令: $2"
          show_help
          exit 1
          ;;
      esac
      ;;
    worker)
      case "${2:-sync}" in
        sync|pull)
          worker_sync_config
          ;;
        daemon|auto)
          worker_start_sync_daemon
          ;;
        diff|compare)
          worker_diff_config
          ;;
        *)
          echo "未知 Worker 命令: $2"
          show_help
          exit 1
          ;;
      esac
      ;;
    help|--help|-h|"")
      show_help
      ;;
    *)
      echo "未知角色: $ROLE"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
