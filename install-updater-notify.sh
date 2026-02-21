#!/bin/bash
# OpenClaw 自动更新提醒 - 安装脚本
# 设置定时检查并在有新版本时发送 Telegram 通知

set -e

echo "🐾 OpenClaw 自动更新提醒 - 安装脚本"
echo "======================================"

WORKSPACE="/root/.openclaw/workspace"
SCRIPT="${WORKSPACE}/openclaw-updater-notify.py"
CHECKER_SCRIPT="${WORKSPACE}/openclaw-checker.py"

# 检查脚本是否存在
if [ ! -f "$SCRIPT" ]; then
    echo "❌ 错误: 未找到 $SCRIPT"
    echo "请确保 openclaw-updater-notify.py 在 workspace 目录中"
    exit 1
fi

chmod +x "$SCRIPT"
chmod +x "$CHECKER_SCRIPT" 2>/dev/null || true

echo ""
echo "📋 安装选项:"
echo "1) 每天检查一次 (早上 9:00)"
echo "2) 每天检查两次 (早上 9:00 和晚上 9:00)"
echo "3) 每小时检查一次"
echo "4) 自定义"
echo "5) 仅运行一次测试"
echo ""
read -p "请选择 [1-5]: " choice

CRON_EXPR=""
case $choice in
    1)
        CRON_EXPR="0 9 * * *"
        DESC="每天早上 9:00"
        ;;
    2)
        CRON_EXPR="0 9,21 * * *"
        DESC="每天早上 9:00 和晚上 9:00"
        ;;
    3)
        CRON_EXPR="0 * * * *"
        DESC="每小时"
        ;;
    4)
        echo ""
        echo "请输入 Cron 表达式 (例如: 0 9 * * * 表示每天9点)"
        echo "格式: 分钟 小时 日期 月份 星期"
        read -p "Cron 表达式: " CRON_EXPR
        DESC="自定义: $CRON_EXPR"
        ;;
    5)
        echo ""
        echo "🧪 运行测试..."
        python3 "$SCRIPT"
        echo ""
        echo "测试完成！如需设置定时任务，请重新运行此脚本。"
        exit 0
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac

echo ""
echo "🔧 设置定时任务: $DESC"
echo "脚本路径: $SCRIPT"

# 创建临时文件
TEMP_CRON=$(mktemp)

# 导出当前 crontab
crontab -l 2>/dev/null > "$TEMP_CRON" || echo "# OpenClaw 自动更新提醒" > "$TEMP_CRON"

# 移除旧的 OpenClaw 检查任务
grep -v "openclaw-updater-notify" "$TEMP_CRON" > "${TEMP_CRON}.new" || true
mv "${TEMP_CRON}.new" "$TEMP_CRON"

# 添加新任务
echo "" >> "$TEMP_CRON"
echo "# OpenClaw 更新检查 - 有新版本时发送 Telegram 通知" >> "$TEMP_CRON"
echo "$CRON_EXPR /usr/bin/python3 $SCRIPT >> /tmp/openclaw-notify.log 2>&1" >> "$TEMP_CRON"

# 安装新的 crontab
crontab "$TEMP_CRON"
rm "$TEMP_CRON"

echo ""
echo "✅ 定时任务已设置!"
echo ""
echo "📊 当前 crontab:"
crontab -l | grep -A1 "OpenClaw"
echo ""
echo "📁 日志文件: /tmp/openclaw-notify.log"
echo ""
echo "🧪 立即运行测试?"
read -p "运行测试 [y/N]: " test_run

if [[ "$test_run" =~ ^[Yy]$ ]]; then
    echo ""
    echo "运行测试..."
    python3 "$SCRIPT"
fi

echo ""
echo "======================================"
echo "🎉 安装完成!"
echo ""
echo "常用命令:"
echo "  查看日志: tail -f /tmp/openclaw-notify.log"
echo "  手动运行: python3 $SCRIPT"
echo "  编辑定时: crontab -e"
echo "  查看状态: crontab -l"
echo ""
