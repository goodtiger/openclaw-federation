#!/usr/bin/env python3
"""
OpenClaw 更新检查器 & 社区动态追踪器
作者: Garfield (加菲)
功能:
1. 检查 OpenClaw 最新版本
2. 获取 GitHub 发布说明
3. 搜索社区热门讨论
"""

import requests
import subprocess
import json
import sys
from datetime import datetime
from packaging import version

# 配置
GITHUB_REPO = "openclaw/openclaw"
GITHUB_API = f"https://api.github.com/repos/{GITHUB_REPO}"
DISCORD_INVITE = "https://discord.com/invite/clawd"
DOCS_URL = "https://docs.openclaw.ai"
CLAWHUB_URL = "https://clawhub.com"

class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.CYAN}{text}{Colors.ENDC}")
    print(f"{Colors.HEADER}{'='*60}{Colors.ENDC}")

def print_section(text):
    print(f"\n{Colors.BLUE}▶ {text}{Colors.ENDC}")

def get_local_version():
    """获取本地安装的 OpenClaw 版本"""
    try:
        result = subprocess.run(
            ["openclaw", "version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except:
        pass
    
    try:
        result = subprocess.run(
            ["openclaw", "--version"],
            capture_output=True,
            text=True,
            timeout=5
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

def get_recent_releases(limit=3):
    """获取最近的 releases"""
    try:
        response = requests.get(
            f"{GITHUB_API}/releases",
            timeout=10,
            headers={"Accept": "application/vnd.github.v3+json"},
            params={"per_page": limit}
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return [{"error": str(e)}]

def get_github_discussions():
    """获取 GitHub Discussions (使用搜索 API)"""
    try:
        # 搜索最近的讨论
        response = requests.get(
            "https://api.github.com/search/issues",
            timeout=10,
            headers={"Accept": "application/vnd.github.v3+json"},
            params={
                "q": f"repo:{GITHUB_REPO} is:discussion",
                "sort": "updated",
                "order": "desc",
                "per_page": 5
            }
        )
        response.raise_for_status()
        return response.json().get("items", [])
    except Exception as e:
        return []

def get_recent_commits(limit=5):
    """获取最近的 commits"""
    try:
        response = requests.get(
            f"{GITHUB_API}/commits",
            timeout=10,
            headers={"Accept": "application/vnd.github.v3+json"},
            params={"per_page": limit}
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        return []

def check_version_update(local_ver, latest_ver):
    """比较版本号"""
    try:
        # 清理版本号
        local_clean = local_ver.lstrip('v').replace('-', '.')
        latest_clean = latest_ver.lstrip('v').replace('-', '.')
        
        local_v = version.parse(local_clean)
        latest_v = version.parse(latest_clean)
        
        if local_v < latest_v:
            return f"{Colors.YELLOW}⚠️  有新版本可用!{Colors.ENDC}"
        elif local_v == latest_v:
            return f"{Colors.GREEN}✅ 已是最新版本{Colors.ENDC}"
        else:
            return f"{Colors.CYAN}ℹ️  本地版本比发布版更新 (可能是开发版){Colors.ENDC}"
    except:
        if local_ver == latest_ver:
            return f"{Colors.GREEN}✅ 版本一致{Colors.ENDC}"
        else:
            return f"{Colors.YELLOW}⚠️  版本不同，请手动检查{Colors.ENDC}"

def format_date(date_str):
    """格式化日期"""
    try:
        dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        return dt.strftime("%Y-%m-%d")
    except:
        return date_str

def main():
    print_header("🐾 OpenClaw 更新检查器")
    print(f"检查时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 1. 本地版本检查
    print_section("本地版本信息")
    local_version = get_local_version()
    if local_version:
        print(f"  {Colors.GREEN}当前版本: {local_version}{Colors.ENDC}")
    else:
        print(f"  {Colors.YELLOW}无法获取本地版本，请确保 openclaw 已安装{Colors.ENDC}")
    
    # 2. 最新 Release 检查
    print_section("GitHub 最新发布")
    latest = get_latest_release()
    
    if "error" in latest:
        print(f"  {Colors.RED}获取失败: {latest['error']}{Colors.ENDC}")
    else:
        latest_tag = latest.get("tag_name", "unknown")
        published = format_date(latest.get("published_at", ""))
        
        print(f"  最新版本: {Colors.BOLD}{latest_tag}{Colors.ENDC}")
        print(f"  发布时间: {published}")
        
        if local_version:
            status = check_version_update(local_version, latest_tag)
            print(f"  更新状态: {status}")
        
        # 显示发布说明摘要
        body = latest.get("body", "")
        if body:
            print(f"\n  {Colors.BOLD}发布说明摘要:{Colors.ENDC}")
            lines = body.split('\n')[:15]  # 只显示前15行
            for line in lines:
                if line.strip():
                    print(f"    {line[:100]}{'...' if len(line) > 100 else ''}")
        
        # 发布链接
        html_url = latest.get("html_url", "")
        if html_url:
            print(f"\n  详情链接: {Colors.CYAN}{html_url}{Colors.ENDC}")
    
    # 3. 最近的 Releases
    print_section("最近发布历史")
    releases = get_recent_releases(5)
    for rel in releases:
        if "error" in rel:
            print(f"  {Colors.RED}获取失败{Colors.ENDC}")
            break
        tag = rel.get("tag_name", "unknown")
        date = format_date(rel.get("published_at", ""))
        name = rel.get("name", "")
        print(f"  • {Colors.BOLD}{tag}{Colors.ENDC} ({date}) - {name[:50]}")
    
    # 4. 最近 Commits
    print_section("最近代码提交")
    commits = get_recent_commits(5)
    for commit in commits:
        if "error" in commit:
            print(f"  {Colors.RED}获取失败{Colors.ENDC}")
            break
        sha = commit.get("sha", "")[:7]
        msg = commit.get("commit", {}).get("message", "").split('\n')[0]
        author = commit.get("commit", {}).get("author", {}).get("name", "")
        print(f"  • {Colors.CYAN}{sha}{Colors.ENDC} {msg[:60]}{'...' if len(msg) > 60 else ''} - {author}")
    
    # 5. GitHub Discussions
    print_section("GitHub 社区讨论")
    discussions = get_github_discussions()
    if discussions:
        for disc in discussions[:5]:
            title = disc.get("title", "")
            url = disc.get("html_url", "")
            comments = disc.get("comments", 0)
            print(f"  • {title[:70]}{'...' if len(title) > 70 else ''}")
            print(f"    {Colors.CYAN}{url}{Colors.ENDC} ({comments} 回复)")
    else:
        print(f"  无法获取讨论列表，请访问: {Colors.CYAN}https://github.com/{GITHUB_REPO}/discussions{Colors.ENDC}")
    
    # 6. 社区资源
    print_section("社区资源")
    print(f"  📖 官方文档:    {Colors.CYAN}{DOCS_URL}{Colors.ENDC}")
    print(f"  💬 Discord:     {Colors.CYAN}{DISCORD_INVITE}{Colors.ENDC}")
    print(f"  🧩 Skill 市场:  {Colors.CYAN}{CLAWHUB_URL}{Colors.ENDC}")
    print(f"  🐙 GitHub:      {Colors.CYAN}https://github.com/{GITHUB_REPO}{Colors.ENDC}")
    
    # 7. 升级建议
    print_section("升级建议")
    if local_version and "error" not in latest:
        latest_tag = latest.get("tag_name", "")
        try:
            local_clean = local_version.lstrip('v').replace('-', '.')
            latest_clean = latest_tag.lstrip('v').replace('-', '.')
            
            if version.parse(local_clean) < version.parse(latest_clean):
                print(f"  {Colors.YELLOW}检测到新版本！升级命令:{Colors.ENDC}")
                print(f"  {Colors.GREEN}  npm update -g openclaw{Colors.ENDC}")
                print(f"  或重新安装:")
                print(f"  {Colors.GREEN}  npm install -g openclaw{Colors.ENDC}")
            else:
                print(f"  {Colors.GREEN}当前已是最新版本，无需升级。{Colors.ENDC}")
        except:
            print(f"  请访问 {Colors.CYAN}https://github.com/{GITHUB_REPO}/releases{Colors.ENDC} 查看升级说明")
    else:
        print(f"  请访问 {Colors.CYAN}https://github.com/{GITHUB_REPO}/releases{Colors.ENDC} 查看升级说明")
    
    print(f"\n{Colors.HEADER}{'='*60}{Colors.ENDC}\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}已取消{Colors.ENDC}")
        sys.exit(0)
    except Exception as e:
        print(f"{Colors.RED}错误: {e}{Colors.ENDC}")
        sys.exit(1)
