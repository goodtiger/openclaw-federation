#!/bin/bash
#
# OpenClaw 联邦部署脚本 (生产级 Hybrid 支持 v2.2)
# 变更: Hybrid 模式下强制隔离 Worker 的状态目录，防止文件锁冲突
#

set -e

# --- 配置 ---
GATEWAY_PORT=18789
SERVICE_NAME_MASTER="openclaw-gateway"
SERVICE_NAME_WORKER="openclaw-worker"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 辅助函数 ---

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测是否为 root 或有 sudo
init_privilege() {
  SUDO_CMD=""
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo &> /dev/null; then
      SUDO_CMD="sudo"
    else
      log_warn "非 root 且无 sudo，安装可能会失败"
    fi
  fi
}

# 获取当前用户的 OpenClaw 目录
resolve_user_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    echo "$HOME"
  fi
}

USER_HOME="$(resolve_user_home)"
OPENCLAW_HOME="$USER_HOME/.openclaw"
WORKER_HOME="$USER_HOME/.openclaw-worker" # Hybrid 模式专用隔离目录
CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"

# 安装 OpenClaw
install_openclaw() {
  if command -v openclaw &> /dev/null; then
    log_info "OpenClaw 已安装: $(openclaw --version)"
    return
  fi

  log_info "正在安装 OpenClaw CLI..."
  if ! command -v npm &> /dev/null; then
    log_info "安装 Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO_CMD bash -
    $SUDO_CMD apt-get install -y nodejs
  fi
  
  $SUDO_CMD npm install -g openclaw
  log_success "OpenClaw 安装完成"
}

# 安装/检查 Tailscale
setup_tailscale() {
  if ! command -v tailscale &> /dev/null; then
    log_info "安装 Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  
  if ! tailscale status &> /dev/null; then
    log_warn "Tailscale 未登录或未启动"
    log_info "请运行: sudo tailscale up"
    exit 1
  fi
  
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
  log_success "Tailscale IP: $TAILSCALE_IP"
}

# --- Master 部署逻辑 ---

deploy_master() {
  log_info ">>> 开始部署 Master (Gateway) 节点 <<<"
  
  mkdir -p "$OPENCLAW_HOME"
  
  # 生成或读取 Token
  local token
  if [[ -f "$OPENCLAW_HOME/.auth-token" ]]; then
    token=$(cat "$OPENCLAW_HOME/.auth-token")
  else
    token=$(openssl rand -hex 32)
    echo "$token" > "$OPENCLAW_HOME/.auth-token"
    chmod 600 "$OPENCLAW_HOME/.auth-token"
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    local backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "发现现有配置文件，正在备份至: $backup_file"
    cp "$CONFIG_FILE" "$backup_file"
    
    if ! command -v jq &> /dev/null; then
      log_info "未检测到 jq，尝试自动安装以进行安全合并..."
      if command -v apt-get &> /dev/null; then
        $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y jq
      elif command -v brew &> /dev/null; then
        brew install jq
      elif command -v yum &> /dev/null; then
        $SUDO_CMD yum install -y jq
      fi
    fi

    if command -v jq &> /dev/null; then
      log_info "安全更新 Gateway 配置 (保留原有的模型、渠道等设置)..."
      jq --arg port "$GATEWAY_PORT" \
         --arg bind "tailnet" \
         --arg token "$token" \
         '.gateway.port = ($port|tonumber) | .gateway.bind = $bind | .gateway.auth.mode = "token" | .gateway.auth.token = $token' \
         "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
      mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
      log_warn "由于缺失 jq 工具，为防止配置覆盖，已跳过配置文件修改！"
      log_warn "请手动编辑 $CONFIG_FILE 设置 gateway.bind 为 tailnet 及对应 token。"
    fi
  else
    # 写入 Master 配置 (强制绑定 Tailnet)
    log_info "生成初始 Gateway 配置..."
    cat > "$CONFIG_FILE" << EOF
{
  "gateway": {
    "port": $GATEWAY_PORT,
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "$token"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "$OPENCLAW_HOME/workspace"
    }
  }
}
EOF
  fi

  # 2. 安装并启动服务
  log_info "注册 Gateway 系统服务..."
  openclaw gateway stop 2>/dev/null || true
  openclaw gateway install --force
  openclaw gateway start
  
  sleep 3
  if openclaw gateway status &> /dev/null; then
    log_success "Master Gateway 已启动!"
    echo ""
    echo "=================================================="
    echo "Master 部署成功信息"
    echo "=================================================="
    echo "Tailscale IP: $TAILSCALE_IP"
    echo "端口:         $GATEWAY_PORT"
    echo "Admin Token:  $token"
    echo ""
    echo "请复制上面的 IP，用于部署 Worker 节点。"
    echo "=================================================="
  else
    log_error "Gateway 启动失败，请运行 'openclaw gateway logs' 查看原因"
    exit 1
  fi
}

# --- Worker / Hybrid 部署逻辑 ---

deploy_worker() {
  local role=$1
  local master_ip=$2
  
  if [[ -z "$master_ip" ]]; then
    log_error "Worker/Hybrid 部署需要指定 Master IP"
    echo "用法: $0 $role <MASTER_TAILSCALE_IP>"
    exit 1
  fi

  local worker_state_dir="$OPENCLAW_HOME" # 默认 Worker 使用标准目录
  
  if [[ "$role" == "hybrid" ]]; then
    log_info ">>> 开始部署 Hybrid (混合) 节点 <<<"
    log_info "模式: 隔离状态目录，避免与本地 Gateway 冲突"
    worker_state_dir="$WORKER_HOME" # Hybrid 模式切换到隔离目录
    mkdir -p "$worker_state_dir"
    # 确保权限正确 (如果是 sudo 运行)
    if [[ -n "${SUDO_USER:-}" ]]; then
      chown -R "$SUDO_USER" "$worker_state_dir"
    fi
  else
    log_info ">>> 开始部署 Worker (纯节点) <<<"
  fi
  
  log_info "目标 Master: $master_ip"

  # 1. 处理本地 Gateway 状态
  if [[ "$role" == "hybrid" ]]; then
    if ! openclaw gateway status &> /dev/null; then
      log_warn "本地 Gateway 未运行，正在尝试启动..."
      openclaw gateway start
      if openclaw gateway status &> /dev/null; then
        log_success "本地 Gateway 已启动 (Hybrid 正常)"
      else
        log_warn "本地 Gateway 启动失败，但这不影响 Worker 连接"
      fi
    else
      log_info "本地 Gateway 正在运行 (保持原样)"
    fi
  else
    # 纯 Worker 模式：确保 Gateway 停止
    if openclaw gateway status &> /dev/null; then
      log_warn "检测到正在运行的 Gateway，正在停止..."
      openclaw gateway stop
      $SUDO_CMD systemctl disable $SERVICE_NAME_MASTER 2>/dev/null || true
      log_success "已停止本地 Gateway (Worker 纯净模式)"
    fi
  fi

  # 2. 创建 Worker 连接服务
  log_info "创建 Worker 连接服务..."
  
  local service_file="/etc/systemd/system/$SERVICE_NAME_WORKER.service"
  local user="${SUDO_USER:-$USER}"
  local node_bin=$(command -v openclaw)
  local connect_url="ws://${master_ip}:${GATEWAY_PORT}"

  # 生成 Systemd Unit
  # 注意：在 Environment 中注入 OPENCLAW_STATE_DIR 以实现隔离
  cat << EOF | $SUDO_CMD tee "$service_file" > /dev/null
[Unit]
Description=OpenClaw Worker Connection (To Master: $master_ip)
After=network.target tailscaled.service

[Service]
Type=simple
User=$user
Restart=always
RestartSec=10
ExecStart=$node_bin nodes connect "$connect_url"
Environment=NODE_ENV=production
Environment=OPENCLAW_STATE_DIR=$worker_state_dir

[Install]
WantedBy=multi-user.target
EOF

  $SUDO_CMD systemctl daemon-reload
  $SUDO_CMD systemctl enable "$SERVICE_NAME_WORKER"
  $SUDO_CMD systemctl restart "$SERVICE_NAME_WORKER"

  log_success "连接服务已启动 ($SERVICE_NAME_WORKER)"
  echo ""
  echo "=================================================="
  if [[ "$role" == "hybrid" ]]; then
    echo "Hybrid 部署成功 (混合模式)"
    echo "- 本地 Gateway: 运行中 (数据在 ~/.openclaw)"
    echo "- 远程 Worker:  运行中 (数据隔离在 ~/.openclaw-worker)"
  else
    echo "Worker 部署成功"
    echo "- 本地 Gateway: 已停止"
    echo "- 远程 Worker:  运行中 (数据在 ~/.openclaw)"
  fi
  echo "=================================================="
  echo "1. 节点正在尝试连接 Master..."
  echo "2. 请现在回到 Master 机器，运行以下命令批准连接："
  echo ""
  echo "   ./manage-federation.sh pending"
  echo "   ./manage-federation.sh approve <Request_ID>"
  echo "=================================================="
}

# --- 主流程 ---

main() {
  local role=$1
  shift
  
  init_privilege
  setup_tailscale
  install_openclaw
  
  case "$role" in
    master)
      deploy_master
      ;;
    worker)
      deploy_worker "worker" "$@"
      ;;
    hybrid)
      deploy_worker "hybrid" "$@"
      ;;
    *)
      echo "用法: $0 {master|worker|hybrid} [args...]"
      echo "  $0 master                   部署主节点 (大脑)"
      echo "  $0 worker <MASTER_IP>       部署纯工作节点 (手脚)"
      echo "  $0 hybrid <MASTER_IP>       部署混合节点 (独立隔离状态)"
      exit 1
      ;;
  esac
}

main "$@"
