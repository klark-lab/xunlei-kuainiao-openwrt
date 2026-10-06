#!/bin/bash
# GitHub 仓库初始化脚本

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[提示]${NC} $1"
}

echo ""
echo "=========================================="
echo "  GitHub 仓库初始化"
echo "=========================================="
echo ""

# 检查是否在项目目录
if [ ! -f "README.md" ] || [ ! -d ".github" ]; then
    echo "错误：请在 xunlei-kuainiao-openwrt 目录中运行此脚本"
    exit 1
fi

# 检查 git 是否安装
if ! command -v git >/dev/null 2>&1; then
    echo "错误：未安装 git"
    echo "Mac 用户可以通过 Homebrew 安装：brew install git"
    exit 1
fi

# 检查 gh CLI 是否安装
if command -v gh >/dev/null 2>&1; then
    USE_GH_CLI=true
    info "检测到 GitHub CLI，将使用它创建仓库"
else
    USE_GH_CLI=false
    warn "未检测到 GitHub CLI，将提供手动操作指南"
    warn "如需安装 GitHub CLI：brew install gh"
fi

echo ""
echo "请选择操作："
echo "1) 初始化本地 Git 仓库"
echo "2) 创建 GitHub 仓库并推送（需要 GitHub CLI）"
echo "3) 仅显示手动操作指南"
echo ""
read -p "请输入选项 [1]: " CHOICE
CHOICE=${CHOICE:-1}

case $CHOICE in
    1)
        # 初始化本地仓库
        info "初始化 Git 仓库..."
        git init
        git add .
        git commit -m "Initial commit: 迅雷快鸟 OpenWrt 提速插件"
        info "本地仓库初始化完成！"
        echo ""
        echo "下一步："
        echo "1. 在 GitHub 上创建新仓库"
        echo "2. 添加远程仓库：git remote add origin https://github.com/您的用户名/xunlei-kuainiao-openwrt.git"
        echo "3. 推送代码：git push -u origin main"
        ;;
    2)
        if [ "$USE_GH_CLI" = false ]; then
            echo "错误：未安装 GitHub CLI，无法自动创建仓库"
            echo "请安装后重试：brew install gh"
            exit 1
        fi

        # 获取用户名
        GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
        if [ -z "$GH_USER" ]; then
            echo "错误：未登录 GitHub CLI"
            echo "请先执行：gh auth login"
            exit 1
        fi

        info "当前 GitHub 用户：$GH_USER"

        # 初始化本地仓库
        info "初始化 Git 仓库..."
        git init
        git add .
        git commit -m "Initial commit: 迅雷快鸟 OpenWrt 提速插件"

        # 创建远程仓库
        info "创建 GitHub 仓库..."
        gh repo create xunlei-kuainiao-openwrt --public --source=. --remote=origin --push

        info "仓库创建成功！"
        echo ""
        echo "仓库地址：https://github.com/$GH_USER/xunlei-kuainiao-openwrt"
        echo ""
        echo "下一步："
        echo "1. 进入仓库的 Actions 页面"
        echo "2. 启用 Actions"
        echo "3. 手动触发编译或推送代码自动编译"
        ;;
    3)
        echo ""
        echo "手动操作步骤："
        echo ""
        echo "1. 在 GitHub 上创建新仓库："
        echo "   - 访问 https://github.com/new"
        echo "   - 仓库名：xunlei-kuainiao-openwrt"
        echo "   - 选择 Public"
        echo "   - 不要初始化 README"
        echo ""
        echo "2. 初始化本地仓库："
        echo "   git init"
        echo "   git add ."
        echo "   git commit -m 'Initial commit'"
        echo ""
        echo "3. 添加远程仓库并推送："
        echo "   git remote add origin https://github.com/您的用户名/xunlei-kuainiao-openwrt.git"
        echo "   git branch -M main"
        echo "   git push -u origin main"
        echo ""
        echo "4. 启用 Actions："
        echo "   - 进入仓库的 Actions 页面"
        echo "   - 点击 'I understand my workflows, go ahead and enable them'"
        echo ""
        echo "5. 触发编译："
        echo "   - 推送代码会自动触发编译"
        echo "   - 或手动触发：Actions -> Build OpenWrt Packages -> Run workflow"
        ;;
    *)
        echo "无效选项"
        exit 1
        ;;
esac

echo ""
info "完成！"
