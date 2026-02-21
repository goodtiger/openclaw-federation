#!/bin/bash
# OpenClaw 快速更新检查 (Bash 版本)
# 轻量级，无需 Python 依赖

set -e

REPO="openclaw/openclaw"
GITHUB_API="https://api.github.com/repos/${REPO}"

echo "=========================================="
echo "🐾 OpenClaw 更新检查器 (Bash 版)"
echo "=========================================="
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 获取本地版本
echo "▶ 本地版本"
LOCAL_VER=$(openclaw version 2>/dev/null || openclaw --version 2>/dev/null || echo "unknown")
echo "  当前版本: $LOCAL_VER"
echo ""

# 获取最新 release
echo "▶ GitHub 最新发布"
LATEST=$(curl -s "${GITHUB_API}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "  最新版本: $LATEST"

if [ "$LOCAL_VER" != "unknown" ] && [ "$LATEST" != "" ]; then
    if [ "$LOCAL_VER" = "$LATEST" ]; then
        echo "  ✅ 已是最新版本"
    else
        echo "  ⚠️  有新版本可用!"
        echo ""
        echo "  升级命令:"
        echo "    npm update -g openclaw"
        echo "  或重新安装:"
        echo "    npm install -g openclaw"
    fi
fi
echo ""

# 获取最近 commits
echo "▶ 最近代码提交"
curl -s "${GITHUB_API}/commits?per_page=5" | grep '"message":' | head -5 | sed -E 's/.*"message": "([^"]+)".*/  • \1/' | cut -c1-80
echo ""

# 社区资源
echo "▶ 社区资源"
echo "  📖 文档:    https://docs.openclaw.ai"
echo "  💬 Discord: https://discord.com/invite/clawd"
echo "  🧩 Skills:  https://clawhub.com"
echo "  🐙 GitHub:  https://github.com/${REPO}"
echo ""
echo "=========================================="
