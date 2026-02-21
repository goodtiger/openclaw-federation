#!/bin/bash
#
# OpenClaw Gateway 绑定模式切换工具
# 在 Worker 节点上使用，切换绑定地址
#

set -e

CONFIG_FILE="/root/.openclaw/openclaw.json"
BACKUP_DIR="/root/.openclaw/.backups"

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

# 显示当前状态
show_status() {
  echo ""
  log_highlight "=== 当前 Gateway 配置 ==="
  echo ""
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "未找到配置文件: $CONFIG_FILE"
    exit 1
  fi
  
  local current_bind=$(jq -r '.gateway.bind' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
  local current_port=$(jq -r '.gateway.port' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
  
  echo "  绑定地址: $current_bind"
  echo "  端口: $current_port"
  echo ""
  
  # 判断当前模式
  if [[ "$current_bind" == "loopback" ]]; then
    log_highlight "当前模式: 本机模式 (loopback)"
    echo "  ✅ 仅可通过 127.0.0.1 访问（本地调试）"
    echo "  ❌ 内网其他机器无法访问"
    echo "  ❌ Tailscale 网络无法访问"
  elif [[ "$current_bind" == "lan" ]]; then
    log_highlight "当前模式: 局域网模式 (lan)"
    echo "  ✅ 可通过内网 IP 访问"
    echo "  ⚠️  可能无法通过 Tailscale 访问（取决于网卡绑定策略）"
    echo "  ⚠️  需要配置防火墙保护"
  elif [[ "$current_bind" == "tailnet" ]]; then
    log_highlight "当前模式: 安全模式 (tailnet)"
    echo "  ✅ 仅可通过 Tailscale 网络访问"
    echo "  ✅ 天然安全，无需防火墙"
    echo "  ❌ 无法通过 127.0.0.1 访问"
    echo "  ❌ 内网其他机器无法直接访问"
  else
    log_warn "当前模式未知: $current_bind"
  fi
  echo ""
}

# 备份配置
backup_config() {
  mkdir -p "$BACKUP_DIR"
  local backup_name="openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP_DIR/$backup_name"
  echo "$backup_name"
}

# 切换到 0.0.0.0 模式
switch_to_all_interfaces() {
  echo ""
  log_highlight "=== 切换到局域网模式 (lan) ==="
  echo ""
  
  # 备份
  local backup=$(backup_config)
  log_success "配置已备份: $backup"
  echo ""
  
  # 修改绑定地址
  jq '.gateway.bind = "lan"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  
  log_success "绑定模式已更新: lan"
  echo ""
  
  # 询问是否重启 Gateway
  read -p "是否立即重启 Gateway 生效? [Y/n]: " confirm
  if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
    restart_gateway
  else
    log_info "请稍后手动重启: openclaw gateway restart"
  fi
  
  echo ""
  log_highlight "=== 切换完成 ==="
  echo ""
  echo "现在你可以:"
  echo "  ✅ 通过内网 IP 访问"
  echo ""
  log_warn "⚠️  注意: 请确保防火墙已配置，避免暴露在公网!"
  echo ""
}

# 切换到 Tailscale IP 模式
switch_to_tailscale() {
  echo ""
  log_highlight "=== 切换到安全模式 (tailnet) ==="
  echo ""
  
  # 获取 Tailscale IP
  local ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
  if [[ -z "$ts_ip" ]]; then
    log_error "无法获取 Tailscale IP，请确保 Tailscale 已启动"
    exit 1
  fi
  
  # 备份
  local backup=$(backup_config)
  log_success "配置已备份: $backup"
  echo ""
  
  # 修改绑定地址
  jq '.gateway.bind = "tailnet"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  
  log_success "绑定模式已更新: tailnet"
  echo ""
  
  # 询问是否重启
  read -p "是否立即重启 Gateway 生效? [Y/n]: " confirm
  if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
    restart_gateway
  else
    log_info "请稍后手动重启: openclaw gateway restart"
  fi
  
  echo ""
  log_highlight "=== 切换完成 ==="
  echo ""
  echo "现在:"
  echo "  ✅ 仅可通过 Tailscale 网络访问"
  echo "  ✅ 天然安全，无需防火墙"
  echo ""
  log_warn "注意:"
  echo "  ❌ 无法通过 127.0.0.1 访问"
  echo "  ❌ 内网其他机器无法直接访问"
  echo ""
}

# 重启 Gateway
restart_gateway() {
  log_info "重启 Gateway..."
  
  if openclaw gateway status &> /dev/null; then
    openclaw gateway stop || true
    sleep 2
  fi
  
  openclaw gateway start
  sleep 2
  
  if openclaw gateway status &> /dev/null; then
    log_success "Gateway 重启成功"
  else
    log_error "Gateway 重启失败，请检查配置"
    exit 1
  fi
}

# 测试连接
test_connection() {
  echo ""
  log_highlight "=== 测试连接 ==="
  echo ""
  
  local current_bind=$(jq -r '.gateway.bind' "$CONFIG_FILE")
  
  # 测试各种访问方式
  echo "测试访问方式:"
  echo ""
  
  # 1. 本地访问（仅当 loopback）
  if [[ "$current_bind" == "loopback" ]]; then
    if curl -s http://127.0.0.1:18789/health &>/dev/null; then
      log_success "✅ 127.0.0.1:18789 可访问"
    else
      log_error "❌ 127.0.0.1:18789 无法访问"
    fi
  else
    echo "  ⏭️  跳过 127.0.0.1 测试（非 loopback 模式）"
  fi
  
  # 2. Tailscale IP（tailnet 模式下必须可访问）
  local ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
  if [[ "$current_bind" == "tailnet" ]]; then
    if [[ -n "$ts_ip" ]]; then
      if curl -s "http://$ts_ip:18789/health" &>/dev/null; then
        log_success "✅ Tailscale ($ts_ip:18789) 可访问"
      else
        log_error "❌ Tailscale ($ts_ip:18789) 无法访问"
      fi
    else
      log_error "❌ 无法获取 Tailscale IP"
    fi
  else
    if [[ -n "$ts_ip" ]]; then
      echo "  ⏭️  未强制测试 Tailscale（当前模式: $current_bind）"
    fi
  fi
  
  echo ""
}

# 回滚到之前的配置
rollback() {
  echo ""
  log_highlight "=== 回滚到之前的配置 ==="
  echo ""
  
  # 列出备份
  local backups=($(ls -t "$BACKUP_DIR"/openclaw.json.backup.* 2>/dev/null | head -5))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    log_error "未找到备份文件"
    exit 1
  fi
  
  echo "可用的备份:"
  local i=1
  for backup in "${backups[@]}"; do
    echo "  $i. $(basename "$backup")"
    ((i++))
  done
  echo ""
  
  read -p "选择要恢复的备份 [1-${#backups[@]}]: " choice
  
  if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#backups[@]} ]]; then
    local selected="${backups[$((choice-1))]}"
    
    # 备份当前
    local current_backup=$(backup_config)
    log_info "当前配置已备份: $current_backup"
    
    # 恢复
    cp "$selected" "$CONFIG_FILE"
    log_success "已恢复到: $(basename "$selected")"
    
    # 询问重启
    read -p "是否立即重启 Gateway? [Y/n]: " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
      restart_gateway
    fi
  else
    log_error "无效选择"
    exit 1
  fi
  
  echo ""
}

# 帮助
show_help() {
  cat << 'EOF'
OpenClaw Gateway 绑定模式切换工具

用法:
  switch-bind-mode.sh [命令]

命令:
  status          显示当前绑定状态
  to-all          切换到 lan 模式（局域网）
  to-tailscale    切换到 tailnet 模式（安全模式）
  test            测试各种访问方式
  rollback        回滚到之前的配置
  help            显示帮助

示例:
  # 查看当前状态
  ./switch-bind-mode.sh status

  # 切换到 0.0.0.0（方便本地调试）
  ./switch-bind-mode.sh to-all

  # 切换到 Tailscale IP（安全模式）
  ./switch-bind-mode.sh to-tailscale

  # 测试连接
  ./switch-bind-mode.sh test

  # 回滚配置
  ./switch-bind-mode.sh rollback

说明:
  loopback: 仅本机访问（127.0.0.1）
  lan: 局域网访问
  tailnet: 仅 Tailscale 网络访问

EOF
}

# 主入口
case "${1:-status}" in
  status|s)
    show_status
    ;;
  to-all|all|0.0.0.0|open)
    switch_to_all_interfaces
    show_status
    ;;
  to-tailscale|tailscale|ts|secure)
    switch_to_tailscale
    show_status
    ;;
  test|t)
    test_connection
    ;;
  rollback|restore|r)
    rollback
    show_status
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
