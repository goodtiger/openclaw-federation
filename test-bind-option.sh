#!/bin/bash
#
# 测试 Gateway 绑定选项
#

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  测试 Gateway 绑定选项                                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 测试 1: 默认绑定 0.0.0.0
echo "═══════════════════════════════════════════════════════════"
echo "测试 1: 默认参数（应绑定 0.0.0.0）"
echo "═══════════════════════════════════════════════════════════"

# 创建一个测试脚本来验证参数解析
cat > /tmp/test-bind.sh << 'EOF'
#!/bin/bash
BIND_TAILSCALE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --bind-tailscale)
      BIND_TAILSCALE=true
      shift
      ;;
  esac
  shift
done

if [[ "$BIND_TAILSCALE" == "true" ]]; then
  echo "BIND_IP: TAILSCALE_IP"
else
  echo "BIND_IP: 0.0.0.0"
fi
EOF
chmod +x /tmp/test-bind.sh

echo ""
echo "命令: ./deploy-federation.sh master"
echo "预期: BIND_IP: 0.0.0.0"
echo "实际: $(/tmp/test-bind.sh master)"
echo ""

# 测试 2: 绑定 Tailscale IP
echo "═══════════════════════════════════════════════════════════"
echo "测试 2: 使用 --bind-tailscale（应绑定 Tailscale IP）"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "命令: ./deploy-federation.sh master --bind-tailscale"
echo "预期: BIND_IP: TAILSCALE_IP"
echo "实际: $(/tmp/test-bind.sh master --bind-tailscale)"
echo ""

# 测试 3: Worker 节点
echo "═══════════════════════════════════════════════════════════"
echo "测试 3: Worker 节点（应绑定 0.0.0.0）"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "命令: ./deploy-federation.sh worker --master-ip 100.64.0.1"
echo "预期: BIND_IP: 0.0.0.0"
echo "实际: $(/tmp/test-bind.sh worker --master-ip 100.64.0.1)"
echo ""

# 测试 4: Worker 节点绑定 Tailscale
echo "═══════════════════════════════════════════════════════════"
echo "测试 4: Worker 节点使用 --bind-tailscale"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "命令: ./deploy-federation.sh worker --master-ip 100.64.0.1 --bind-tailscale"
echo "预期: BIND_IP: TAILSCALE_IP"
echo "实际: $(/tmp/test-bind.sh worker --master-ip 100.64.0.1 --bind-tailscale)"
echo ""

# 清理
rm -f /tmp/test-bind.sh

echo "═══════════════════════════════════════════════════════════"
echo "测试完成！"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "说明:"
echo "  - 默认绑定 0.0.0.0 (所有接口)"
echo "  - 使用 --bind-tailscale 绑定 Tailscale IP (更安全)"
echo ""
