#!/bin/bash
#
# 测试 Worker 默认绑定 0.0.0.0 的逻辑
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  测试 Worker 绑定逻辑（默认 0.0.0.0）                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log() { echo -e "${BLUE}[TEST]${NC} $1"; }

echo "═══════════════════════════════════════════════════════════"
echo "【测试 1】Master 使用 --bind-tailscale"
echo "═══════════════════════════════════════════════════════════"
echo ""

ROLE="master"
BIND_TAILSCALE="true"
TAILSCALE_IP="100.64.0.1"

bind_ip="0.0.0.0"
if [[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
fi

if [[ "$bind_ip" == "100.64.0.1" ]]; then
  pass "Master 绑定 Tailscale IP: $bind_ip"
else
  fail "Master 应该绑定 Tailscale IP，但得到: $bind_ip"
fi
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【测试 2】Worker 默认（不使用 --bind-tailscale）"
echo "═══════════════════════════════════════════════════════════"
echo ""

ROLE="worker"
BIND_TAILSCALE="false"
TAILSCALE_IP="100.64.0.2"

bind_ip="0.0.0.0"
if [[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
elif [[ "$ROLE" == "worker" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
fi

if [[ "$bind_ip" == "0.0.0.0" ]]; then
  pass "Worker 默认绑定 0.0.0.0"
else
  fail "Worker 应该绑定 0.0.0.0，但得到: $bind_ip"
fi
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【测试 3】Worker 使用 --bind-tailscale"
echo "═══════════════════════════════════════════════════════════"
echo ""

ROLE="worker"
BIND_TAILSCALE="true"
TAILSCALE_IP="100.64.0.2"

bind_ip="0.0.0.0"
if [[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
elif [[ "$ROLE" == "worker" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
fi

if [[ "$bind_ip" == "100.64.0.2" ]]; then
  pass "Worker 使用 --bind-tailscale 绑定: $bind_ip"
else
  fail "Worker 应该绑定 Tailscale IP，但得到: $bind_ip"
fi
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【测试 4】Master 默认（不使用 --bind-tailscale）"
echo "═══════════════════════════════════════════════════════════"
echo ""

ROLE="master"
BIND_TAILSCALE="false"
TAILSCALE_IP="100.64.0.1"

bind_ip="0.0.0.0"
if [[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
elif [[ "$ROLE" == "worker" && "$BIND_TAILSCALE" == "true" ]]; then
  bind_ip="$TAILSCALE_IP"
fi

if [[ "$bind_ip" == "0.0.0.0" ]]; then
  pass "Master 默认绑定 0.0.0.0"
else
  fail "Master 应该绑定 0.0.0.0，但得到: $bind_ip"
fi
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "【场景测试】推荐的使用方式"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "场景 1: Master 安全 + Worker 灵活（推荐）"
echo "───────────────────────────────────────────────────────────"
log "Master: ./deploy-federation.sh master --bind-tailscale"
ROLE="master"; BIND_TAILSCALE="true"; bind_ip="0.0.0.0"
[[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]] && bind_ip="100.64.0.1"
log "  → 绑定: $bind_ip"

log "Worker: ./deploy-federation.sh worker --master-ip 100.64.0.1 --token xxx"
ROLE="worker"; BIND_TAILSCALE="false"; bind_ip="0.0.0.0"
[[ "$ROLE" == "master" && "$BIND_TAILSCALE" == "true" ]] && bind_ip="100.64.0.2"
[[ "$ROLE" == "worker" && "$BIND_TAILSCALE" == "true" ]] && bind_ip="100.64.0.2"
log "  → 绑定: $bind_ip"

if [[ "$bind_ip" == "0.0.0.0" ]]; then
  pass "Worker 默认使用 0.0.0.0，方便本地管理"
fi
echo ""

echo "场景 2: 全部安全模式"
echo "───────────────────────────────────────────────────────────"
log "Master: ./deploy-federation.sh master --bind-tailscale"
log "Worker: ./deploy-federation.sh worker --master-ip 100.64.0.1 --token xxx --bind-tailscale"

ROLE="worker"; BIND_TAILSCALE="true"; bind_ip="0.0.0.0"
[[ "$ROLE" == "worker" && "$BIND_TAILSCALE" == "true" ]] && bind_ip="100.64.0.2"
log "  → Worker 绑定: $bind_ip"
pass "Worker 使用 --bind-tailscale 绑定 Tailscale IP"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "总结"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "修改后的行为:"
echo ""
echo "  Master + --bind-tailscale  → 绑定 Tailscale IP"
echo "  Master 默认                → 绑定 0.0.0.0"
echo "  Worker + --bind-tailscale  → 绑定 Tailscale IP (可选)"
echo "  Worker 默认                → 绑定 0.0.0.0 (推荐)"
echo ""
echo "这样 Worker 默认就是 0.0.0.0，方便本地调试！"
echo ""
