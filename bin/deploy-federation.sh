#!/bin/bash
#
# OpenClaw + Tailscale 联邦部署脚本 - Token 共享版
# 支持跨机器同步 Token
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
GATEWAY_PORT=18789
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

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
CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"
BACKUP_DIR="$OPENCLAW_HOME/.backups"

ROLE="${1:-}"
shift || true

# 解析参数
MASTER_IP=""
NODE_NAME=""
NODE_SKILLS=""
PRESERVE_CONFIG=true
IMPORT_TOKEN=""      # 从其他机器导入的 Token
IMPORT_TOKEN_FILE="" # 指定 Token 文件路径
BIND_TAILSCALE=false         # 绑定 Tailscale 网络（tailnet）
ENABLE_CONFIG_CENTER=false   # 默认不启用配置中心
BIND_MODE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --master-ip)
      MASTER_IP="$2"
      shift 2
      ;;
    --node-name)
      NODE_NAME="$2"
      shift 2
      ;;
    --skills)
      NODE_SKILLS="$2"
      shift 2
      ;;
    --token)
      IMPORT_TOKEN="$2"
      shift 2
      ;;
    --enable-config-center)
      ENABLE_CONFIG_CENTER=true
      shift
      ;;
    --token-file)
      IMPORT_TOKEN_FILE="$2"
      shift 2
      ;;
    --bind-tailscale)
      BIND_TAILSCALE=true
      shift
      ;;
    --bind-mode)
      BIND_MODE="$2"
      shift 2
      ;;
    --overwrite-config)
      PRESERVE_CONFIG=false
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}未知参数: $1${NC}"
      exit 1
      ;;
  esac
done

show_help() {
  cat << 'EOF' | sed "s/__SCRIPT_NAME__/$SCRIPT_NAME/g"
OpenClaw + Tailscale 联邦部署脚本（Token 共享版）

用法:
  ./__SCRIPT_NAME__ [ROLE] [OPTIONS]

角色:
  master    部署主控节点（VPS/公网服务器）
  worker    部署工作节点（家庭服务器/Mac/Pi）

选项:
  --master-ip IP          主节点的 Tailscale IP（worker 必需）
  --node-name NAME        节点名称（如: home-server, mac-pc）
  --skills "s1 s2"        要安装的技能列表
  --token TOKEN           指定共享 Token（worker 使用）
  --token-file PATH       从文件读取 Token（worker 使用）
  --bind-tailscale        Gateway 绑定 Tailscale 网络（等价于 --bind-mode tailnet）
  --bind-mode MODE        绑定模式: loopback/lan/tailnet/auto/custom
  --enable-config-center  启用配置中心（默认不启用）
  --overwrite-config      完全覆盖配置（默认会保留现有配置）

环境变量:
  FEDERATION_TOKEN        共享 Token（优先级高于 --token）
  TOKEN_FILE              Token 文件路径（默认: ~/.openclaw/.federation-token）
  OPENCLAW_HOME           OpenClaw 工作目录（默认: ~/.openclaw 或 sudo 用户家目录）
  ALLOW_UNSAFE_TAILSCALE_INSTALL=true  允许使用 curl | sh 安装 Tailscale（不推荐）
  SHOW_FULL_TOKEN=true    显示完整 Token（默认仅脱敏显示）

Token 共享方式:

  方式 1: 复制粘贴（最简单）
    主节点部署后显示 Token，手动复制到工作节点

  方式 2: 文件复制
    主节点: cat ~/.openclaw/.federation-token
    工作节点: 保存到相同路径，或使用 --token-file

  方式 3: SSH 传输
    主节点 → 工作节点: ssh user@worker "echo TOKEN > ~/.openclaw/.federation-token"

  方式 4: 环境变量
    export FEDERATION_TOKEN="主节点显示的 Token"
    ./__SCRIPT_NAME__ worker --master-ip 100.64.0.1

示例:
  # 部署主节点（生成新 Token）
  ./__SCRIPT_NAME__ master

  # 工作节点方式 1: 直接使用 Token
  ./__SCRIPT_NAME__ worker --master-ip 100.64.0.1 --token "abc123..."

  # 工作节点方式 2: 从文件读取 Token
  ./__SCRIPT_NAME__ worker --master-ip 100.64.0.1 --token-file /path/to/token.txt

  # 工作节点方式 3: 环境变量
  export FEDERATION_TOKEN="abc123..."
  ./__SCRIPT_NAME__ worker --master-ip 100.64.0.1

EOF
}

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_highlight() { echo -e "${CYAN}$1${NC}"; }

npm_has_package() {
  local pkg=$1
  command -v npm &> /dev/null || return 1
  npm list -g --depth=0 "$pkg" > /dev/null 2>&1
}

is_valid_bind_mode() {
  local mode=$1
  case "$mode" in
    loopback|lan|tailnet|auto|custom)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_has_tailscale() {
  if command -v dpkg &> /dev/null; then
    dpkg -s tailscale > /dev/null 2>&1 && return 0
  fi
  if command -v rpm &> /dev/null; then
    rpm -q tailscale > /dev/null 2>&1 && return 0
  fi
  local brew_bin
  brew_bin=$(resolve_brew_bin || true)
  if [[ -n "$brew_bin" ]]; then
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
      sudo -u "$SUDO_USER" "$brew_bin" list --formula tailscale > /dev/null 2>&1 && return 0
    else
      "$brew_bin" list --formula tailscale > /dev/null 2>&1 && return 0
    fi
  fi
  return 1
}

is_ubuntu() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]]
    return $?
  fi
  return 1
}

ubuntu_codename() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ -n "${VERSION_CODENAME:-}" ]]; then
      echo "$VERSION_CODENAME"
      return 0
    fi
    if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
      echo "$UBUNTU_CODENAME"
      return 0
    fi
  fi
  return 1
}

install_tailscale_ubuntu_repo() {
  local codename
  codename=$(ubuntu_codename) || return 1

  log_info "添加 Tailscale 官方 APT 源: $codename"
  mkdir -p /usr/share/keyrings
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" \
    | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list" \
    | tee /etc/apt/sources.list.d/tailscale.list > /dev/null

  apt-get update -qq || true
  apt-get install -y -qq tailscale
}

resolve_brew_bin() {
  if command -v brew &> /dev/null; then
    command -v brew
    return 0
  fi
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    echo "/opt/homebrew/bin/brew"
    return 0
  fi
  if [[ -x "/usr/local/bin/brew" ]]; then
    echo "/usr/local/bin/brew"
    return 0
  fi
  return 1
}

# 获取或生成 Token
get_or_generate_token() {
  # 优先级: 环境变量 > 命令行参数 --token > 命令行参数 --token-file > 本地文件 > 生成新 Token
  
  # 1. 检查环境变量
  if [[ -n "${FEDERATION_TOKEN:-}" ]]; then
    TOKEN="$FEDERATION_TOKEN"
    log_info "从环境变量 FEDERATION_TOKEN 读取 Token"
    save_token "$TOKEN"
    return 0
  fi
  
  # 2. 检查命令行 --token 参数
  if [[ -n "$IMPORT_TOKEN" ]]; then
    TOKEN="$IMPORT_TOKEN"
    log_info "使用命令行指定的 Token"
    save_token "$TOKEN"
    return 0
  fi
  
  # 3. 检查命令行 --token-file 参数
  if [[ -n "$IMPORT_TOKEN_FILE" ]]; then
    if [[ -f "$IMPORT_TOKEN_FILE" ]]; then
      TOKEN=$(cat "$IMPORT_TOKEN_FILE" | tr -d '[:space:]')
      log_info "从文件 $IMPORT_TOKEN_FILE 读取 Token"
      save_token "$TOKEN"
      return 0
    else
      log_error "指定的 Token 文件不存在: $IMPORT_TOKEN_FILE"
      exit 1
    fi
  fi
  
  # 4. 检查本地 Token 文件
  if [[ -f "$TOKEN_FILE" ]]; then
    TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
    if [[ -n "$TOKEN" ]]; then
      log_info "使用本地 Token 文件"
      return 0
    fi
  fi
  
  # 5. 如果是 worker 角色，但没有 Token，报错
  if [[ "$ROLE" == "worker" ]]; then
    log_error "Worker 节点需要提供 Token"
    echo ""
    log_info "请使用以下方式之一提供 Token:"
    log_highlight "  1. --token \"你的Token\""
    log_highlight "  2. --token-file /path/to/token.txt"
    log_highlight "  3. export FEDERATION_TOKEN=\"你的Token\""
    log_highlight "  4. 在主节点执行后，将 Token 保存到 $TOKEN_FILE"
    echo ""
    log_info "获取 Token 的方法:"
    log_highlight "  在主节点上执行: cat $TOKEN_FILE"
    echo ""
    exit 1
  fi
  
  # 6. 如果是 master 角色，生成新 Token
  TOKEN=$(openssl rand -hex 32)
  save_token "$TOKEN"
  log_success "生成新 Token: ${TOKEN:0:16}..."
}

# 保存 Token 到文件
save_token() {
  local token=$1
  mkdir -p "$(dirname "$TOKEN_FILE")"
  echo "$token" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
}

# 显示 Token 导出帮助
show_token_export_help() {
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  log_highlight "=== Token 共享方式（在其他机器上使用） ==="
  echo "═══════════════════════════════════════════════════════════"
  echo ""

  local token_display
  if [[ "${SHOW_FULL_TOKEN:-false}" == "true" ]]; then
    token_display="$TOKEN"
  else
    token_display="${TOKEN:0:4}...${TOKEN: -4}"
  fi
  
  log_info "方式 1: 复制 Token 文件内容"
  echo "  Token: ${YELLOW}$token_display${NC}"
  echo "  在其他机器上运行:"
  echo -e "  ${GREEN}./$SCRIPT_NAME worker --master-ip $TAILSCALE_IP --token-file $TOKEN_FILE${NC}"
  echo ""
  
  log_info "方式 2: SSH 传输 Token 文件"
  echo "  从主节点复制到工作节点:"
  echo -e "  ${CYAN}scp $TOKEN_FILE user@worker:$TOKEN_FILE${NC}"
  echo "  然后在工作节点上运行:"
  echo -e "  ${GREEN}./$SCRIPT_NAME worker --master-ip $TAILSCALE_IP${NC}"
  echo ""
  
  log_info "方式 3: 直接 SSH 写入"
  echo -e "  ${CYAN}ssh user@worker \"mkdir -p ~/.openclaw && echo '$TOKEN' > ~/.openclaw/.federation-token\"${NC}"
  echo ""
  
  log_info "方式 4: 环境变量"
  echo -e "  在工作节点上:"
  echo -e "  ${CYAN}export FEDERATION_TOKEN=\"\$(cat $TOKEN_FILE)\"${NC}"
  echo -e "  ${GREEN}./$SCRIPT_NAME worker --master-ip $TAILSCALE_IP${NC}"
  echo ""
  
  if [[ "${SHOW_FULL_TOKEN:-false}" != "true" ]]; then
    log_info "提示: 如需显示完整 Token，可临时设置 SHOW_FULL_TOKEN=true 再运行部署脚本"
  fi
  log_warn "重要: 请保存好这个 Token，所有工作节点需要使用相同的 Token！"
  echo ""
}

# 检查 jq 是否安装
check_jq() {
  if ! command -v jq &> /dev/null; then
    log_info "安装 jq（用于安全合并配置）..."
    if command -v apt-get &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq jq
    elif command -v yum &> /dev/null; then
      yum install -y jq
    elif command -v brew &> /dev/null; then
      brew install jq
    else
      log_warn "无法自动安装 jq，将使用基础配置模式"
      return 1
    fi
  fi
  return 0
}

# 备份现有配置
backup_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    mkdir -p "$BACKUP_DIR"
    local backup_name="openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_DIR/$backup_name"
    log_success "配置已备份到: $BACKUP_DIR/$backup_name"
    echo "$backup_name"
  else
    echo ""
  fi
}

# 安全合并配置
merge_config_with_jq() {
  local role=$1
  local bind_mode=$2
  local backup_name=$3
  
  log_info "使用 jq 安全合并配置..."
  
  local gateway_config=$(cat << EOF
{
  "gateway": {
    "port": $GATEWAY_PORT,
    "bind": "$bind_mode",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$TOKEN"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "meta": {
    "lastTouchedVersion": "$(openclaw version 2>/dev/null | head -1 | awk '{print $2}' || echo 'unknown')",
    "lastTouchedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  }
}
EOF
)
  
  jq -s '.[0] * .[1]' "$CONFIG_FILE" <(echo "$gateway_config") > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  log_success "配置已安全合并"
}

# 基础配置模式
create_basic_config() {
  local role=$1
  local bind_mode=$2
  
  log_warn "使用基础配置模式"
  
  cat > "$CONFIG_FILE" << EOF
{
  "meta": {
    "lastTouchedVersion": "$(openclaw version 2>/dev/null | head -1 | awk '{print $2}' || echo 'unknown')",
    "lastTouchedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  },
  "gateway": {
    "port": $GATEWAY_PORT,
    "bind": "$bind_mode",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$TOKEN"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/root/.openclaw/workspace",
      "compaction": { "mode": "safeguard" }
    }
  },
  "channels": {
    "telegram": { "enabled": true, "dmPolicy": "pairing", "groupPolicy": "allowlist" }
  }
}
EOF
}

# 配置 Gateway
configure_gateway_safe() {
  local role=$1
  local bind_mode=$2
  
  log_info "配置 OpenClaw Gateway ($role 模式)..."
  mkdir -p "$(dirname "$CONFIG_FILE")"

  if ! is_valid_bind_mode "$bind_mode"; then
    log_error "无效的绑定模式: $bind_mode"
    log_info "可选: loopback/lan/tailnet/auto/custom"
    exit 1
  fi
  
  local backup_name=$(backup_config)
  
  if [[ "$PRESERVE_CONFIG" == "true" && -f "$BACKUP_DIR/$backup_name" ]]; then
    if check_jq; then
      merge_config_with_jq "$role" "$bind_mode" "$backup_name"
    else
      log_warn "无法安全合并配置"
      read -p "继续将覆盖配置? [y/N]: " choice
      [[ "$choice" =~ ^[Yy]$ ]] || exit 0
      create_basic_config "$role" "$bind_mode"
    fi
  else
    create_basic_config "$role" "$bind_mode"
  fi
  
  if [[ -f "$CONFIG_FILE" ]]; then
    log_success "Gateway 配置完成"
    log_info "绑定模式: $bind_mode"
    if command -v jq &> /dev/null; then
      jq '.gateway | {port, bind, auth: {mode: .auth.mode}}' "$CONFIG_FILE" 2>/dev/null || true
    fi
  fi
}

# 检查 root 权限
check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "请使用 root 权限运行 (sudo)"
    exit 1
  fi
}

# 检测操作系统
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    log_info "检测到系统: $NAME"
  fi
}

# 安装并配置 Tailscale
setup_tailscale() {
  log_info "检查 Tailscale..."
  
  if ! command -v tailscale &> /dev/null; then
    log_info "安装 Tailscale（安全模式，优先包管理器）..."
    if ! install_tailscale_safe; then
      if [[ "${ALLOW_UNSAFE_TAILSCALE_INSTALL:-false}" == "true" ]]; then
        log_warn "安全安装失败，使用不安全模式（curl | sh）"
        curl -fsSL https://tailscale.com/install.sh | sh
      else
        log_error "无法通过包管理器安装 Tailscale"
        log_info "请手动安装后重试，或设置 ALLOW_UNSAFE_TAILSCALE_INSTALL=true 允许使用 curl | sh"
        exit 1
      fi
    fi
  else
    log_success "Tailscale 已安装"
  fi
  
  if ! tailscale status &> /dev/null; then
    log_info "启动 Tailscale，请在浏览器中完成登录..."
    tailscale up
  else
    log_success "Tailscale 已登录"
  fi
  
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)
  if [[ -z "$TAILSCALE_IP" ]]; then
    log_error "无法获取 Tailscale IP"
    exit 1
  fi
  log_success "Tailscale IP: $TAILSCALE_IP"
}

install_tailscale_safe() {
  if command -v tailscale &> /dev/null; then
    return 0
  fi

  if pkg_has_tailscale; then
    log_warn "检测到 Tailscale 已通过包管理器安装，但命令不可用"
    log_warn "请检查 PATH 或重新登录后再试"
    return 0
  fi

  if command -v apt-get &> /dev/null; then
    log_info "尝试使用 apt 安装..."
    apt-get update -qq || true
    if apt-get install -y -qq tailscale; then
      return 0
    fi
    if is_ubuntu; then
      log_warn "APT 源中未找到 tailscale，尝试添加官方源..."
      if install_tailscale_ubuntu_repo; then
        return 0
      fi
    fi
  elif command -v dnf &> /dev/null; then
    log_info "尝试使用 dnf 安装..."
    if dnf install -y tailscale; then
      return 0
    fi
  elif command -v yum &> /dev/null; then
    log_info "尝试使用 yum 安装..."
    if yum install -y tailscale; then
      return 0
    fi
  else
    local brew_bin
    brew_bin=$(resolve_brew_bin || true)
    if [[ -n "$brew_bin" ]]; then
      if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        log_info "尝试使用 brew 安装（以用户 $SUDO_USER 运行）..."
        if sudo -u "$SUDO_USER" "$brew_bin" install tailscale; then
          return 0
        fi
      elif [[ $EUID -eq 0 ]]; then
        log_warn "检测到 brew，但当前为 root，无法安全运行 brew"
      else
        log_info "尝试使用 brew 安装..."
        if "$brew_bin" install tailscale; then
          return 0
        fi
      fi
    fi
  fi

  return 1
}

# 检查 OpenClaw
check_openclaw() {
  log_info "检查 OpenClaw..."
  
  if command -v openclaw &> /dev/null; then
    log_success "OpenClaw 已安装"
    return 0
  fi

  if npm_has_package "openclaw"; then
    log_success "OpenClaw 已安装（npm 全局）"
    log_warn "openclaw 命令未在 PATH 中，跳过重复安装"
    return 0
  fi
  
  log_info "安装 OpenClaw..."
  if ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi
  npm install -g openclaw
  log_success "OpenClaw 安装完成"
}

# 启动 Gateway
start_gateway() {
  log_info "启动 OpenClaw Gateway..."
  
  if openclaw gateway status &> /dev/null; then
    log_warn "Gateway 已在运行，重启中..."
    openclaw gateway stop 2>/dev/null || true
    sleep 2
  fi
  
  openclaw gateway start
  sleep 2
  
  if openclaw gateway status &> /dev/null; then
    log_success "Gateway 启动成功"
  else
    log_error "Gateway 启动失败"
    exit 1
  fi
}

# 安装技能
install_skills() {
  local skills=$1
  [[ -z "$skills" ]] && return 0
  
  log_info "安装技能: $skills"
  for skill in $skills; do
    openclaw skills install "$skill" 2>/dev/null || log_warn "$skill 安装失败"
  done
}

# 开放防火墙
open_firewall() {
  log_info "配置防火墙..."
  if command -v ufw &> /dev/null; then
    ufw allow $GATEWAY_PORT/tcp 2>/dev/null || true
  elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$GATEWAY_PORT/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
  fi
}

# Worker 节点信息显示
show_worker_info() {
  local master_ip=$1
  local node_name=$2
  
  [[ -z "$master_ip" ]] && { log_error "Worker 需要 --master-ip"; exit 1; }
  [[ -z "$node_name" ]] && node_name=$(hostname -s)
  
  local my_ip=$(tailscale ip -4 | head -1)
  
  cat > "/root/.openclaw/.node-info.json" << EOF
{
  "name": "$node_name",
  "tailscale_ip": "$my_ip",
  "master_ip": "$master_ip",
  "skills": "$NODE_SKILLS",
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  log_success "工作节点配置完成！"
  echo ""
  log_highlight "=== 节点信息 ==="
  cat "/root/.openclaw/.node-info.json"
  echo ""
  log_highlight "=== 在主节点执行以下命令添加此节点 ==="
  echo ""
  echo -e "${GREEN}openclaw pair approve \\\n  --name \"$node_name\" \\\n  --url \"ws://$my_ip:$GATEWAY_PORT\" \\\n  --token \"${TOKEN:0:16}...\"${NC}"
  echo ""
}

# Master 节点信息显示
show_master_info() {
  log_success "主节点部署完成！"
  echo ""
  log_highlight "=== 管理命令 ==="
  echo ""
  echo "查看所有节点:"
  echo -e "  ${CYAN}openclaw nodes list${NC}"
  echo ""
  echo "添加新节点:"
  echo -e "  ${CYAN}openclaw pair approve --name <名称> --url ws://<IP>:$GATEWAY_PORT --token <token>${NC}"
  echo ""
  echo "Token 文件位置:"
  echo -e "  ${CYAN}$TOKEN_FILE${NC}"
}

# 主入口
main() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║     OpenClaw + Tailscale 联邦部署脚本 (Token 共享版)      ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  [[ -z "$ROLE" ]] && { show_help; exit 1; }
  [[ "$ROLE" != "master" && "$ROLE" != "worker" ]] && { log_error "无效角色"; exit 1; }
  
  check_root
  detect_os
  
  # 获取 Token
  get_or_generate_token
  
  setup_tailscale
  check_openclaw
  
  # 决定绑定模式
  local bind_mode="$BIND_MODE"
  if [[ -z "$bind_mode" && "$BIND_TAILSCALE" == "true" ]]; then
    bind_mode="tailnet"
  fi
  if [[ -z "$bind_mode" ]]; then
    # 默认使用 lan，保持与历史 0.0.0.0 行为一致
    bind_mode="lan"
  fi

  if ! is_valid_bind_mode "$bind_mode"; then
    log_error "无效的绑定模式: $bind_mode"
    log_info "可选: loopback/lan/tailnet/auto/custom"
    exit 1
  fi

  case "$bind_mode" in
    loopback)
      log_info "Gateway 将绑定 loopback（仅本机访问）"
      ;;
    lan)
      log_info "Gateway 将绑定 lan（局域网访问）"
      log_warn "如需通过 Tailscale 访问，请使用 --bind-tailscale 或 --bind-mode tailnet"
      ;;
    tailnet)
      log_info "Gateway 将绑定 tailnet（Tailscale 网络）"
      log_warn "注意: tailnet 模式下无法通过 127.0.0.1 访问"
      ;;
    auto)
      log_info "Gateway 将绑定 auto（自动选择）"
      ;;
    custom)
      log_warn "Gateway 绑定 custom 需要进一步配置，请参考官方文档"
      ;;
  esac
  
  if [[ -f "$CONFIG_FILE" && "$PRESERVE_CONFIG" == "true" ]]; then
    echo ""
    log_warn "检测到现有 OpenClaw 配置"
    log_info "本脚本将保留所有原有设置，只修改 gateway 部分"
    read -p "继续部署? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { log_info "已取消"; exit 0; }
  fi
  
  configure_gateway_safe "$ROLE" "$bind_mode"
  
  [[ "$ROLE" == "master" ]] && open_firewall
  
  start_gateway
  install_skills "$NODE_SKILLS"
  
  if [[ "$ROLE" == "master" ]]; then
    show_master_info
    show_token_export_help
    
    # 配置中心选项
    echo ""
    if [[ "$ENABLE_CONFIG_CENTER" == "true" ]]; then
      log_info "正在启动配置中心..."
      if [[ -f "$SCRIPT_DIR/config-center.sh" ]]; then
        "$SCRIPT_DIR/config-center.sh" master start
        log_success "配置中心已启动"
      elif [[ -f "/root/.openclaw/workspace/config-center.sh" ]]; then
        /root/.openclaw/workspace/config-center.sh master start
        log_success "配置中心已启动"
      else
        log_warn "配置中心脚本不存在，跳过"
      fi
    else
      log_info "配置中心未启用（使用 --enable-config-center 启用）"
      log_info "如需手动启动，请运行: config-center.sh master start"
    fi
    
    # 健康检查提示
    echo ""
    log_info "提示: 可以安装健康检查服务监控节点状态"
    log_info "运行: health-check.sh install"
  else
    show_worker_info "$MASTER_IP" "$NODE_NAME"
    
    # Worker 自动注册和配置同步提示
    echo ""
    log_info "可选操作:"
    log_info "  1. 自动注册到 Master: auto-register.sh"
    log_info "  2. 同步配置（如启用配置中心）: config-center.sh worker sync"
  fi
  
  echo ""
  log_success "部署完成！"
}

main
