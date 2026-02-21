#!/bin/bash
#
# 联邦任务共享系统演示
#

TEST_DIR="/tmp/task-share-demo-$$"
export SHARED_DIR="$TEST_DIR/shared"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║     OpenClaw 联邦任务共享系统演示                                    ║"
echo "║     Master-Worker 任务协作演示                                       ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
ok() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
log() { echo -e "${BLUE}[DEMO]${NC} $1"; }

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "══════════════════════════════════════════════════════════════════════"
echo "【场景】Master 分配任务，Worker 执行并反馈进度"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "步骤 1: 初始化任务系统（所有节点执行一次）"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh init"
echo ""

mkdir -p "$SHARED_DIR/tasks"/{queue,active,done,archive}
echo '{"tasks": [], "last_update": "'$(date -Iseconds)'"}' > "$SHARED_DIR/tasks/index.json"

ok "  ✓ 任务系统初始化完成"
ok "  ✓ 共享目录: $SHARED_DIR/tasks"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【阶段 1】Master 创建任务"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "步骤 2: Master 创建部署任务"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh create \"部署 Nginx\" worker1 high \"在 worker1 上部署 nginx\""
echo ""

# 创建任务
TASK_FILE="$SHARED_DIR/tasks/queue/task-$(date +%Y%m%d)-$(openssl rand -hex 4).json"
cat > "$TASK_FILE" << 'EOF'
{
  "id": "task-20260221-a1b2c3d4",
  "title": "部署 Nginx",
  "description": "在 worker1 上部署 nginx",
  "status": "pending",
  "priority": "high",
  "assignee": "worker1",
  "from": "master",
  "created_at": "2026-02-21T10:00:00Z",
  "updated_at": "2026-02-21T10:00:00Z",
  "started_at": null,
  "completed_at": null,
  "result": null,
  "progress": 0,
  "logs": []
}
EOF

ok "  ✓ 任务创建成功"
ok "  ✓ 任务 ID: task-20260221-a1b2c3d4"
ok "  ✓ 分配给: worker1"
ok "  ✓ 优先级: high"
echo ""

info "步骤 3: Master 查看任务列表"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh list"
echo ""

printf "  %-20s %-20s %-10s %-10s %-10s\n" "ID" "标题" "状态" "优先级" "负责人"
printf "  %-20s %-20s %-10s %-10s %-10s\n" "─────────────────" "─────────────────" "────────" "────────" "────────"
printf "  %-20s %-20s %-10s %-10s %-10s\n" "task-20260221-a1b2c3d4" "部署 Nginx" "pending" "high" "worker1"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【阶段 2】Worker 领取并执行任务"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "步骤 4: Worker1 领取任务"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh claim worker1"
echo ""

# 移动任务到 active
mv "$TASK_FILE" "$SHARED_DIR/tasks/active/"

ok "  ✓ Worker1 领取任务成功"
ok "  ✓ 任务状态: pending → active"
ok "  ✓ 任务移动到: tasks/active/"
echo ""

info "步骤 5: Worker1 更新进度（25%）"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh update task-20260221-a1b2c3d4 25 \"开始拉取 nginx 镜像\""
echo ""

# 更新任务文件
cat > "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json" << 'EOF'
{
  "id": "task-20260221-a1b2c3d4",
  "title": "部署 Nginx",
  "description": "在 worker1 上部署 nginx",
  "status": "active",
  "priority": "high",
  "assignee": "worker1",
  "from": "master",
  "created_at": "2026-02-21T10:00:00Z",
  "updated_at": "2026-02-21T10:05:00Z",
  "started_at": "2026-02-21T10:01:00Z",
  "completed_at": null,
  "result": null,
  "progress": 25,
  "logs": [
    {"time": "2026-02-21T10:01:00Z", "message": "任务被 worker1 领取"},
    {"time": "2026-02-21T10:05:00Z", "node": "worker1", "progress": 25, "message": "开始拉取 nginx 镜像"}
  ]
}
EOF

ok "  ✓ 进度更新: 25%"
ok "  ✓ 日志记录: 开始拉取 nginx 镜像"
echo ""

read -p "按 Enter 继续..."
echo ""

info "步骤 6: Worker1 更新进度（75%）"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh update task-20260221-a1b2c3d4 75 \"镜像拉取完成，启动容器\""
echo ""

jq '.progress = 75 | .updated_at = "2026-02-21T10:08:00Z" | .logs += [{"time": "2026-02-21T10:08:00Z", "node": "worker1", "progress": 75, "message": "镜像拉取完成，启动容器"}]' "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json" > "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json.tmp"
mv "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json.tmp" "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json"

ok "  ✓ 进度更新: 75%"
ok "  ✓ 日志记录: 镜像拉取完成，启动容器"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【阶段 3】Worker 完成任务"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "步骤 7: Worker1 完成任务"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh complete task-20260221-a1b2c3d4 \"部署成功，访问 http://worker1:80\""
echo ""

# 移动任务到 done
mv "$SHARED_DIR/tasks/active/task-20260221-a1b2c3d4.json" "$SHARED_DIR/tasks/done/"

jq '.status = "completed" | .result = "部署成功，访问 http://worker1:80" | .completed_at = "2026-02-21T10:10:00Z" | .updated_at = "2026-02-21T10:10:00Z" | .progress = 100 | .logs += [{"time": "2026-02-21T10:10:00Z", "node": "worker1", "message": "任务完成: completed"}]' "$SHARED_DIR/tasks/done/task-20260221-a1b2c3d4.json" > "$SHARED_DIR/tasks/done/task-20260221-a1b2c3d4.json.tmp"
mv "$SHARED_DIR/tasks/done/task-20260221-a1b2c3d4.json.tmp" "$SHARED_DIR/tasks/done/task-20260221-a1b2c3d4.json"

ok "  ✓ 任务完成"
ok "  ✓ 结果: 部署成功，访问 http://worker1:80"
ok "  ✓ 任务状态: active → completed"
ok "  ✓ 任务移动到: tasks/done/"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【阶段 4】Master 查看结果"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "步骤 8: Master 查看任务详情"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh show task-20260221-a1b2c3d4"
echo ""

ok "  任务详情:"
echo ""
cat << 'EOF'
  {
    "id": "task-20260221-a1b2c3d4",
    "title": "部署 Nginx",
    "description": "在 worker1 上部署 nginx",
    "status": "completed",
    "priority": "high",
    "assignee": "worker1",
    "from": "master",
    "created_at": "2026-02-21T10:00:00Z",
    "updated_at": "2026-02-21T10:10:00Z",
    "started_at": "2026-02-21T10:01:00Z",
    "completed_at": "2026-02-21T10:10:00Z",
    "result": "部署成功，访问 http://worker1:80",
    "progress": 100,
    "logs": [
      {"time": "2026-02-21T10:01:00Z", "message": "任务被 worker1 领取"},
      {"time": "2026-02-21T10:05:00Z", "node": "worker1", "progress": 25, "message": "开始拉取 nginx 镜像"},
      {"time": "2026-02-21T10:08:00Z", "node": "worker1", "progress": 75, "message": "镜像拉取完成，启动容器"},
      {"time": "2026-02-21T10:10:00Z", "node": "worker1", "message": "任务完成: completed"}
    ]
  }
EOF

echo ""

info "步骤 9: Master 查看统计"
echo "──────────────────────────────────────────────────────────────────────"
echo ""
echo "  $ ./task-share.sh stats"
echo ""

ok "  任务统计:"
echo ""
echo "    待处理 (pending):  0"
echo "    进行中 (active):   0"
echo "    已完成 (done):     1"
echo "    ─────────────────────────"
echo "    总计:              1"
echo ""

read -p "按 Enter 继续..."
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【更多功能】"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

info "批量创建任务:"
echo "  $ ./task-share.sh create \"备份数据库\" worker2 normal \"每日数据库备份\""
echo "  $ ./task-share.sh create \"更新证书\" any high \"更新 SSL 证书\""
echo ""

info "Worker 自动领取任意任务:"
echo "  $ ./task-share.sh claim worker2"
echo ""

info "查看所有任务:"
echo "  $ ./task-share.sh list all"
echo ""

info "清理旧任务:"
echo "  $ ./task-share.sh cleanup 7  # 归档7天前的任务"
echo ""

echo "══════════════════════════════════════════════════════════════════════"
echo "【总结】"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
ok "联邦任务共享系统功能:"
echo ""
echo "  ✅ Master 创建任务并分配给 Worker"
echo "  ✅ Worker 领取任务并开始执行"
echo "  ✅ Worker 实时更新进度和日志"
echo "  ✅ Master 随时查看任务状态"
echo "  ✅ Worker 完成任务并提交结果"
echo "  ✅ 所有任务历史可追溯"
echo ""
info "实现方式:"
echo ""
echo "  • 基于文件系统（无需数据库）"
echo "  • 通过 Syncthing/NFS 同步共享目录"
echo "  • JSON 格式，易于阅读和解析"
echo "  • 支持任务优先级、进度追踪、日志记录"
echo ""
