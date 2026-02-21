#!/bin/bash
#
# OpenClaw 配置管理工具
# 用于备份、恢复和合并配置
#

CONFIG_FILE="/root/.openclaw/openclaw.json"
BACKUP_DIR="/root/.openclaw/.backups"

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

show_help() {
  cat << 'EOF'
OpenClaw 配置管理工具

用法:
  ./config-manager.sh <命令> [选项]

命令:
  backup              立即备份当前配置
  list                列出所有备份
  restore <备份文件>   恢复到指定备份
  restore-latest      恢复到最新备份
  diff <备份文件>      比较当前配置和备份的差异
  merge <备份文件>     交互式合并配置
  clean               清理旧备份（保留最近10个）

示例:
  ./config-manager.sh backup
  ./config-manager.sh list
  ./config-manager.sh restore openclaw.json.backup.20260221_143052
  ./config-manager.sh diff openclaw.json.backup.20260221_143052

EOF
}

# 确保备份目录存在
init_backup_dir() {
  mkdir -p "$BACKUP_DIR"
}

# 备份当前配置
do_backup() {
  init_backup_dir
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "未找到配置文件: $CONFIG_FILE"
    exit 1
  fi
  
  local backup_name="openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP_DIR/$backup_name"
  
  # 同时备份到带标签的文件，方便识别
  local latest_link="$BACKUP_DIR/openclaw.json.backup.latest"
  ln -sf "$backup_name" "$latest_link"
  
  log_success "配置已备份: $BACKUP_DIR/$backup_name"
  
  # 显示配置摘要
  if command -v jq &> /dev/null; then
    echo ""
    log_info "配置摘要:"
    jq '{gateway: .gateway, channels: (.channels | keys), models: (.models // "N/A")}' "$CONFIG_FILE" 2>/dev/null || true
  fi
}

# 列出所有备份
list_backups() {
  init_backup_dir
  
  echo ""
  log_highlight "=== 配置备份列表 ==="
  echo ""
  
  local backups=($(ls -t "$BACKUP_DIR"/openclaw.json.backup.* 2>/dev/null | grep -v ".latest$"))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    log_warn "未找到备份文件"
    exit 0
  fi
  
  printf "%-5s %-40s %-20s %s\n" "序号" "备份文件" "时间" "大小"
  echo "─────────────────────────────────────────────────────────────────────"
  
  local i=1
  for backup in "${backups[@]}"; do
    local filename=$(basename "$backup")
    local mtime=$(stat -c %y "$backup" 2>/dev/null | cut -d'.' -f1)
    local size=$(du -h "$backup" 2>/dev/null | cut -f1)
    printf "%-5s %-40s %-20s %s\n" "$i" "$filename" "$mtime" "$size"
    ((i++))
  done
  
  echo ""
  log_info "共 ${#backups[@]} 个备份文件"
}

# 恢复配置
do_restore() {
  local backup_file=$1
  
  if [[ -z "$backup_file" ]]; then
    log_error "请指定备份文件"
    log_info "使用: $0 restore <备份文件名>"
    log_info "或使用: $0 restore-latest"
    exit 1
  fi
  
  # 如果提供的是相对路径，转换为完整路径
  if [[ ! "$backup_file" =~ ^/ ]]; then
    backup_file="$BACKUP_DIR/$backup_file"
  fi
  
  if [[ ! -f "$backup_file" ]]; then
    log_error "备份文件不存在: $backup_file"
    exit 1
  fi
  
  # 验证 JSON 格式
  if command -v jq &> /dev/null; then
    if ! jq empty "$backup_file" 2>/dev/null; then
      log_error "备份文件 JSON 格式无效"
      exit 1
    fi
  fi
  
  # 备份当前配置（以防万一）
  if [[ -f "$CONFIG_FILE" ]]; then
    local emergency_backup="$BACKUP_DIR/openclaw.json.emergency.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$emergency_backup"
    log_info "当前配置已紧急备份: $emergency_backup"
  fi
  
  # 恢复
  cp "$backup_file" "$CONFIG_FILE"
  log_success "配置已恢复: $backup_file"
  
  # 提示重启
  echo ""
  log_warn "配置已更改，请重启 OpenClaw Gateway:"
  log_highlight "  openclaw gateway restart"
}

# 恢复到最新备份
restore_latest() {
  local latest=$(ls -t "$BACKUP_DIR"/openclaw.json.backup.* 2>/dev/null | grep -v ".latest$" | head -1)
  
  if [[ -z "$latest" ]]; then
    log_error "未找到备份文件"
    exit 1
  fi
  
  log_info "将恢复到最新备份: $(basename "$latest")"
  read -p "确认? [y/N]: " confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    do_restore "$latest"
  else
    log_info "已取消"
  fi
}

# 比较差异
do_diff() {
  local backup_file=$1
  
  if [[ -z "$backup_file" ]]; then
    log_error "请指定备份文件"
    exit 1
  fi
  
  if [[ ! "$backup_file" =~ ^/ ]]; then
    backup_file="$BACKUP_DIR/$backup_file"
  fi
  
  if [[ ! -f "$backup_file" ]]; then
    log_error "备份文件不存在: $backup_file"
    exit 1
  fi
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "当前配置文件不存在"
    exit 1
  fi
  
  echo ""
  log_highlight "=== 配置差异 (当前 vs 备份) ==="
  echo ""
  
  if command -v diff &> /dev/null; then
    diff -u "$backup_file" "$CONFIG_FILE" | head -100 || true
  else
    log_warn "未安装 diff 命令"
    echo "备份文件: $backup_file"
    echo "当前文件: $CONFIG_FILE"
  fi
}

# 交互式合并（高级）
do_merge() {
  local backup_file=$1
  
  if [[ -z "$backup_file" ]]; then
    log_error "请指定备份文件"
    exit 1
  fi
  
  if [[ ! "$backup_file" =~ ^/ ]]; then
    backup_file="$BACKUP_DIR/$backup_file"
  fi
  
  if [[ ! -f "$backup_file" ]]; then
    log_error "备份文件不存在"
    exit 1
  fi
  
  if ! command -v jq &> /dev/null; then
    log_error "需要 jq 工具来进行配置合并"
    exit 1
  fi
  
  echo ""
  log_highlight "=== 交互式配置合并 ==="
  echo ""
  
  # 显示两个配置的关键部分
  log_info "备份配置中的主要设置:"
  jq '{channels: (.channels | keys), models: (.models // "N/A"), gateway: .gateway}' "$backup_file" 2>/dev/null || true
  
  echo ""
  log_info "当前配置中的主要设置:"
  jq '{channels: (.channels | keys), models: (.models // "N/A"), gateway: .gateway}' "$CONFIG_FILE" 2>/dev/null || true
  
  echo ""
  log_warn "合并操作将:"
  log_highlight "  1. 保留当前配置的 gateway（联邦设置）"
  log_highlight "  2. 从备份恢复其他所有设置"
  echo ""
  read -p "继续合并? [y/N]: " confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    # 备份当前
    local temp_backup="$BACKUP_DIR/openclaw.json.pre-merge.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$temp_backup"
    
    # 合并：备份文件 + 当前 gateway
    jq -s '.[0] + {gateway: .[1].gateway}' "$backup_file" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    log_success "配置已合并"
    log_info "紧急备份: $temp_backup"
  else
    log_info "已取消"
  fi
}

# 清理旧备份
clean_backups() {
  init_backup_dir
  
  local backups=($(ls -t "$BACKUP_DIR"/openclaw.json.backup.* 2>/dev/null | grep -v ".latest$"))
  local count=${#backups[@]}
  
  if [[ $count -le 10 ]]; then
    log_info "备份文件数量 ($count) 正常，无需清理"
    return 0
  fi
  
  log_info "找到 $count 个备份，将保留最新的 10 个"
  
  local to_delete=(${backups[@]:10})
  
  for file in "${to_delete[@]}"; do
    rm -f "$file"
    log_info "已删除: $(basename "$file")"
  done
  
  log_success "清理完成"
}

# 主入口
case "${1:-}" in
  backup|b)
    do_backup
    ;;
  list|ls|l)
    list_backups
    ;;
  restore|r)
    do_restore "$2"
    ;;
  restore-latest|rl)
    restore_latest
    ;;
  diff|d)
    do_diff "$2"
    ;;
  merge|m)
    do_merge "$2"
    ;;
  clean|c)
    clean_backups
    ;;
  help|--help|-h|"")
    show_help
    ;;
  *)
    log_error "未知命令: $1"
    show_help
    exit 1
    ;;
esac
