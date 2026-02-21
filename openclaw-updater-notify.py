#!/usr/bin/env python3
"""
OpenClaw 更新自动提醒器
当检测到有新版本时，发送 Telegram 通知
"""

import requests
import subprocess
import json
import sys
import os
from datetime import datetime
from packaging import version

# 配置
GITHUB_REPO = "openclaw/openclaw"
GITHUB_API = f"https://api.github.com/repos/{GITHUB_REPO}"
STATE_FILE = "/root/.openclaw/workspace/.openclaw-checker-state.json"

def send_telegram_notification(message):
    """通过 OpenClaw 发送 Telegram 通知"""
    try:
        # 使用 openclaw message 命令发送
        cmd = [
            "openclaw", "message", "send",
            "--target", "telegram:5145113446",
            "--message", message
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.returncode == 0
    except Exception as e:
        print(f"发送通知失败: {e}")
        return False

def get_local_version():
    """获取本地安装的 OpenClaw 版本"""
    try:
        result = subprocess.run(
            ["openclaw", "version"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except:
        pass
    return None

def get_latest_release():
    """从 GitHub 获取最新 release 信息"""
    try:
        response = requests.get(
            f"{GITHUB_API}/releases/latest",
            timeout=10,
            headers={"Accept": "application/vnd.github.v3+json"}
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return {"error": str(e)}

def load_state():
    """加载上次检查的状态"""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return {"last_notified_version": None, "last_check": None}

def save_state(state):
    """保存检查状态"""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)

def check_and_notify():
    """检查更新并发送通知"""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 开始检查 OpenClaw 更新...")
    
    state = load_state()
    local_version = get_local_version()
    latest = get_latest_release()
    
    if "error" in latest:
        print(f"获取最新版本失败: {latest['error']}")
        return False
    
    latest_tag = latest.get("tag_name", "")
    latest_body = latest.get("body", "")[:500]  # 截取前500字符
    
    # 检查是否需要通知（有新版本且未通知过）
    need_notify = False
    
    if local_version:
        try:
            local_clean = local_version.lstrip('v').replace('-', '.')
            latest_clean = latest_tag.lstrip('v').replace('-', '.')
            
            local_v = version.parse(local_clean)
            latest_v = version.parse(latest_clean)
            
            if latest_v > local_v:
                # 有新版本
                if state.get("last_notified_version") != latest_tag:
                    need_notify = True
        except:
            # 版本号解析失败，直接比较字符串
            if local_version != latest_tag:
                if state.get("last_notified_version") != latest_tag:
                    need_notify = True
    else:
        # 无法获取本地版本，检查是否有新版本发布
        if state.get("last_notified_version") != latest_tag:
            need_notify = True
    
    if need_notify:
        # 构建通知消息
        emoji = "🎉" if local_version and latest_tag != local_version else "📢"
        
        message = f"""{emoji} **OpenClaw 更新提醒**

发现新版本: **{latest_tag}**
"""
        
        if local_version:
            message += f"当前版本: `{local_version}`\n"
        
        message += f"""
📋 **更新摘要:**
{latest_body[:300]}{'...' if len(latest_body) > 300 else ''}

🔗 **详情:** https://github.com/{GITHUB_REPO}/releases/tag/{latest_tag}

💻 **升级命令:**
```
npm update -g openclaw
```
或
```
npm install -g openclaw
```
"""
        
        print(f"检测到新版本 {latest_tag}，发送通知...")
        
        if send_telegram_notification(message):
            print("通知发送成功!")
            # 更新状态
            state["last_notified_version"] = latest_tag
            state["last_check"] = datetime.now().isoformat()
            save_state(state)
            return True
        else:
            print("通知发送失败")
            return False
    else:
        print(f"当前已是最新版本 ({latest_tag})，无需通知")
        # 更新检查时间
        state["last_check"] = datetime.now().isoformat()
        if not state.get("last_notified_version"):
            state["last_notified_version"] = latest_tag
        save_state(state)
        return True

if __name__ == "__main__":
    try:
        success = check_and_notify()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n已取消")
        sys.exit(0)
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)
