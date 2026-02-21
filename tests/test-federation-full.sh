#!/bin/bash
#
# OpenClaw 联邦部署 - 完整沙盒测试
# 在隔离环境中模拟多机部署流程
#

set -e

# 测试环境根目录
TEST_ROOT="/tmp/openclaw-federation-sandbox-$$"
mkdir -p "$TEST_ROOT"

# 模拟机器目录
MASTER_DIR="$TEST_ROOT/master-node"
WORKER1_DIR="$TEST_ROOT/worker1-home"
WORKER2_DIR="$TEST_ROOT/worker2-mac"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw 联邦部署 - 完整沙盒测试                          ║"
echo "║  隔离环境: $TEST_ROOT"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[TEST]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}$1${NC}"; }

# 清理函数
cleanup() {
  echo ""
  log "清理测试环境..."
  rm -rf "$TEST_ROOT"
  log "测试环境已清理"
}
trap cleanup EXIT

# 创建模拟机器环境
setup_mock_env() {
  log "创建模拟机器环境..."
  
  # 主节点 (VPS)
  mkdir -p "$MASTER_DIR/root/.openclaw"
  echo "100.64.0.1" > "$MASTER_DIR/tailscale-ip"
  
  # 工作节点 1 (家庭服务器)
  mkdir -p "$WORKER1_DIR/root/.openclaw"
  echo "100.64.0.2" > "$WORKER1_DIR/tailscale-ip"
  
  # 工作节点 2 (Mac)
  mkdir -p "$WORKER2_DIR/root/.openclaw"
  echo "100.64.0.3" > "$WORKER2_DIR/tailscale-ip"
  
  # 创建模拟的现有配置（带有一些自定义设置）
  cat > "$WORKER1_DIR/root/.openclaw/openclaw.json" << 'EOF'
{
  "meta": { "version": "2026.2.19" },
  "gateway": {
    "port": 18789,
    "bind": "127.0.0.1",
    "auth": { "mode": "token", "token": "old-local-token" }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "8022xxxx:xxxxxxxx",
      "allowFrom": ["5145113446"]
    },
    "discord": {
      "enabled": false
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "openai-iflow": {
        "baseUrl": "http://127.0.0.1:3000"
      },
      "claude-kiro": {
        "baseUrl": "http://127.0.0.1:3001"
      }
    }
  },
  "important_custom_setting": "这个配置必须保留",
  "user_preferences": {
    "theme": "dark",
    "language": "zh-CN"
  }
}
EOF
  
  pass "模拟环境创建完成"
  echo ""
  info "模拟机器:"
  echo "  Master (VPS):        100.64.0.1 - $MASTER_DIR"
  echo "  Worker1 (Home):      100.64.0.2 - $WORKER1_DIR"
  echo "  Worker2 (Mac):       100.64.0.3 - $WORKER2_DIR"
  echo ""
}

# 全局变量存储 Token
GLOBAL_TOKEN=""

# 模拟主节点部署
deploy_master() {
  echo "═══════════════════════════════════════════════════════════"
  info "【阶段 1】主节点 (VPS) 部署"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  log "生成共享 Token..."
  GLOBAL_TOKEN=$(openssl rand -hex 32)
  echo "$GLOBAL_TOKEN" > "$MASTER_DIR/root/.openclaw/.federation-token"
  chmod 600 "$MASTER_DIR/root/.openclaw/.federation-token"
  
  log "创建主节点 Gateway 配置..."
  cat > "$MASTER_DIR/root/.openclaw/openclaw.json" << EOF
{
  "meta": {
    "version": "2026.2.19",
    "federationRole": "master",
    "deployedAt": "$(date -Iseconds)"
  },
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.1",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$GLOBAL_TOKEN"
    },
    "tailscale": {
      "mode": "off"
    }
  }
}
EOF
  
  pass "主节点部署完成"
  info "Token: ${GLOBAL_TOKEN:0:16}..."
  info "保存位置: $MASTER_DIR/root/.openclaw/.federation-token"
  echo ""
}

# 模拟 Token 共享到工作节点
share_token() {
  echo "═══════════════════════════════════════════════════════════"
  info "【阶段 2】Token 共享到工作节点"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  log "使用方式 1: 复制粘贴 Token"
  
  # Worker 1
  echo "$GLOBAL_TOKEN" > "$WORKER1_DIR/root/.openclaw/.federation-token"
  chmod 600 "$WORKER1_DIR/root/.openclaw/.federation-token"
  log "Token 已写入 Worker1: $WORKER1_DIR/root/.openclaw/.federation-token"
  
  # Worker 2
  echo "$GLOBAL_TOKEN" > "$WORKER2_DIR/root/.openclaw/.federation-token"
  chmod 600 "$WORKER2_DIR/root/.openclaw/.federation-token"
  log "Token 已写入 Worker2: $WORKER2_DIR/root/.openclaw/.federation-token"
  
  pass "Token 共享完成"
  echo ""
}

# 模拟配置合并（关键测试）
merge_worker_config() {
  local worker_dir=$1
  local worker_name=$2
  local worker_ip=$3
  local worker_token=$4
  
  log "[$worker_name] 备份现有配置..."
  mkdir -p "$worker_dir/root/.openclaw/.backups"
  cp "$worker_dir/root/.openclaw/openclaw.json" \
     "$worker_dir/root/.openclaw/.backups/openclaw.json.backup.$(date +%Y%m%d_%H%M%S)"
  
  log "[$worker_name] 合并配置（保留原有设置）..."
  
  # 读取现有配置
  local original_config=$(cat "$worker_dir/root/.openclaw/openclaw.json")
  
  # 使用 jq 合并（如果可用）
  if command -v jq &> /dev/null; then
    # 先创建临时文件存储 gateway 配置
    local gateway_tmp="$worker_dir/gateway_tmp.json"
    cat > "$gateway_tmp" << EOF
{
  "gateway": {
    "port": 18789,
    "bind": "$worker_ip",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$worker_token"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "meta": {
    "federationRole": "worker",
    "mergedAt": "$(date -Iseconds)"
  }
}
EOF
    jq -s '.[0] * .[1]' "$worker_dir/root/.openclaw/openclaw.json" "$gateway_tmp" > "$worker_dir/root/.openclaw/openclaw.json.tmp"
    mv "$worker_dir/root/.openclaw/openclaw.json.tmp" "$worker_dir/root/.openclaw/openclaw.json"
    rm -f "$gateway_tmp"
  else
    # 基础模式：直接覆盖 gateway
    log "[$worker_name] 使用基础合并模式..."
    # 简化的合并逻辑
    cat > "$worker_dir/root/.openclaw/openclaw.json" << EOF
{
  "meta": {
    "version": "2026.2.19",
    "federationRole": "worker",
    "note": "原有配置已备份"
  },
  "gateway": {
    "port": 18789,
    "bind": "$worker_ip",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$worker_token"
    }
  }
}
EOF
  fi
  
  pass "[$worker_name] 配置合并完成"
}

# 模拟工作节点部署
deploy_workers() {
  echo "═════════════════════════���═════════════════════════════════"
  info "【阶段 3】工作节点部署"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  # Worker 1 (有现有配置)
  log "部署 Worker1 (家庭服务器) - 有现有配置，测试合并..."
  merge_worker_config "$WORKER1_DIR" "home-server" "100.64.0.2" "$GLOBAL_TOKEN"
  
  # 创建节点信息文件
  cat > "$WORKER1_DIR/root/.openclaw/.node-info.json" << EOF
{
  "name": "home-server",
  "tailscale_ip": "100.64.0.2",
  "master_ip": "100.64.0.1",
  "skills": "docker k8s tmux",
  "registered_at": "$(date -Iseconds)"
}
EOF
  echo ""
  
  # Worker 2 (全新安装)
  log "部署 Worker2 (Mac) - 全新安装..."
  cat > "$WORKER2_DIR/root/.openclaw/openclaw.json" << EOF
{
  "meta": {
    "federationRole": "worker",
    "deployedAt": "$(date -Iseconds)"
  },
  "gateway": {
    "port": 18789,
    "bind": "100.64.0.3",
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$GLOBAL_TOKEN"
    },
    "tailscale": {
      "mode": "off"
    }
  }
}
EOF
  
  cat > "$WORKER2_DIR/root/.openclaw/.node-info.json" << EOF
{
  "name": "mac-pc",
  "tailscale_ip": "100.64.0.3",
  "master_ip": "100.64.0.1",
  "skills": "apple-notes",
  "registered_at": "$(date -Iseconds)"
}
EOF
  
  pass "Worker2 部署完成"
  echo ""
}

# 验证配置
verify_configs() {
  echo "═══════════════════════════════════════════════════════════"
  info "【阶段 4】验证配置"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  local all_pass=true
  
  # 1. 验证所有节点使用相同的 Token
  log "验证 Token 一致性..."
  MASTER_TOKEN=$(cat "$MASTER_DIR/root/.openclaw/.federation-token")
  WORKER1_TOKEN=$(cat "$WORKER1_DIR/root/.openclaw/.federation-token")
  WORKER2_TOKEN=$(cat "$WORKER2_DIR/root/.openclaw/.federation-token")
  
  if [[ "$MASTER_TOKEN" == "$WORKER1_TOKEN" && "$MASTER_TOKEN" == "$WORKER2_TOKEN" ]]; then
    pass "所有节点使用相同的 Token"
  else
    error "Token 不一致！"
    all_pass=false
  fi
  echo ""
  
  # 2. 验证 Worker1 的配置合并（关键测试）
  log "验证 Worker1 配置合并..."
  
  if command -v jq &> /dev/null; then
    local worker1_config=$(cat "$WORKER1_DIR/root/.openclaw/openclaw.json")
    
    # 检查原有配置是否保留
    if echo "$worker1_config" | jq -e '.channels.telegram.enabled' &>/dev/null; then
      pass "Worker1: channels.telegram 配置已保留"
    else
      error "Worker1: channels.telegram 配置丢失！"
      all_pass=false
    fi
    
    if echo "$worker1_config" | jq -e '.models.providers' &>/dev/null; then
      pass "Worker1: models 配置已保留"
    else
      error "Worker1: models 配置丢失！"
      all_pass=false
    fi
    
    if echo "$worker1_config" | jq -e '.important_custom_setting' &>/dev/null; then
      pass "Worker1: 自定义设置已保留"
    else
      error "Worker1: 自定义设置丢失！"
      all_pass=false
    fi
    
    if echo "$worker1_config" | jq -e '.user_preferences.theme' &>/dev/null; then
      pass "Worker1: user_preferences 已保留"
    else
      error "Worker1: user_preferences 丢失！"
      all_pass=false
    fi
    
    # 检查新的 gateway 配置
    local new_bind=$(echo "$worker1_config" | jq -r '.gateway.bind')
    if [[ "$new_bind" == "100.64.0.2" ]]; then
      pass "Worker1: gateway.bind 已更新为 Tailscale IP"
    else
      error "Worker1: gateway.bind 未正确更新"
      all_pass=false
    fi
    
    local new_token=$(echo "$worker1_config" | jq -r '.gateway.auth.token')
    if [[ "$new_token" == "$MASTER_TOKEN" ]]; then
      pass "Worker1: gateway.auth.token 已更新为共享 Token"
    else
      error "Worker1: gateway.auth.token 未正确更新"
      all_pass=false
    fi
  else
    warn "未安装 jq，跳过详细配置验证"
  fi
  echo ""
  
  # 3. 验证 Gateway 配置
  log "验证 Gateway 配置..."
  for dir in "$MASTER_DIR" "$WORKER1_DIR" "$WORKER2_DIR"; do
    local name=$(basename "$dir")
    if [[ -f "$dir/root/.openclaw/openclaw.json" ]]; then
      local bind=$(jq -r '.gateway.bind' "$dir/root/.openclaw/openclaw.json" 2>/dev/null || echo "unknown")
      pass "$name: Gateway 配置存在，bind=$bind"
    else
      error "$name: Gateway 配置不存在！"
      all_pass=false
    fi
  done
  echo ""
  
  # 4. 验证备份
  log "验证配置备份..."
  if [[ -d "$WORKER1_DIR/root/.openclaw/.backups" ]]; then
    local backup_count=$(ls -1 "$WORKER1_DIR/root/.openclaw/.backups" 2>/dev/null | wc -l)
    pass "Worker1: 已创建 $backup_count 个备份"
  else
    warn "Worker1: 未找到备份目录"
  fi
  echo ""
  
  # 5. 验证节点信息文件
  log "验证节点信息文件..."
  for dir in "$WORKER1_DIR" "$WORKER2_DIR"; do
    local name=$(basename "$dir")
    if [[ -f "$dir/root/.openclaw/.node-info.json" ]]; then
      local node_name=$(jq -r '.name' "$dir/root/.openclaw/.node-info.json" 2>/dev/null)
      pass "$name: 节点信息文件存在 (name=$node_name)"
    else
      error "$name: 节点信息文件不存在！"
      all_pass=false
    fi
  done
  echo ""
  
  $all_pass
}

# 显示配置摘要
show_summary() {
  echo "═══════════════════════════════════════════════════════════"
  info "【配置摘要】"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  info "主节点 (VPS) 配置:"
  if command -v jq &> /dev/null; then
    jq '.gateway | {bind, port, auth: {mode: .auth.mode}}' "$MASTER_DIR/root/.openclaw/openclaw.json"
  fi
  echo ""
  
  info "Worker1 (家庭服务器) 合并后的配置:"
  if command -v jq &> /dev/null; then
    echo "关键设置保留情况:"
    jq '{channels: (.channels | keys), models: (.models // "N/A") | type, custom: .important_custom_setting, theme: .user_preferences.theme, gateway_ip: .gateway.bind}' "$WORKER1_DIR/root/.openclaw/openclaw.json"
  fi
  echo ""
  
  info "Token 一致性检查:"
  echo "  主节点:   ${MASTER_TOKEN:0:16}..."
  echo "  Worker1:  ${WORKER1_TOKEN:0:16}..."
  echo "  Worker2:  ${WORKER2_TOKEN:0:16}..."
  if [[ "$MASTER_TOKEN" == "$WORKER1_TOKEN" && "$MASTER_TOKEN" == "$WORKER2_TOKEN" ]]; then
    pass "所有节点 Token 相同 ✓"
  fi
  echo ""
}

# 模拟节点添加命令
show_register_commands() {
  echo "═══════════════════════════════════════════════════════════"
  info "【在主节点执行的注册命令】"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  
  info "添加 Worker1 (家庭服务器):"
  echo -e "${GREEN}openclaw pair approve \\\n  --name \"home-server\" \\\n  --url \"ws://100.64.0.2:18789\" \\\n  --token \"${MASTER_TOKEN:0:16}...\"${NC}"
  echo ""
  
  info "添加 Worker2 (Mac):"
  echo -e "${GREEN}openclaw pair approve \\\n  --name \"mac-pc\" \\\n  --url \"ws://100.64.0.3:18789\" \\\n  --token \"${MASTER_TOKEN:0:16}...\"${NC}"
  echo ""
}

# 主测试流程
main() {
  setup_mock_env
  
  # 阶段 1: 部署主节点（设置 GLOBAL_TOKEN）
  deploy_master
  
  # 阶段 2: 共享 Token
  share_token
  
  # 阶段 3: 部署工作节点
  deploy_workers
  
  # 阶段 4: 验证
  if verify_configs; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              所有测试通过！✅                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
  else
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              部分测试失败！❌                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
  fi
  
  # 显示摘要
  show_summary
  show_register_commands
  
  # 显示文件结构
  echo "═══════════════════════════════════════════════════════════"
  info "【生成的文件结构】"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  find "$TEST_ROOT" -type f | head -20 | while read f; do
    echo "  $f"
  done
  echo ""
}

main
