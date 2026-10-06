#!/bin/bash
# 迅雷快鸟 OpenWrt 一键部署脚本
# 用于 Mac/Linux 直接部署到路由器

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

# 获取路由器信息
get_router_info() {
    echo ""
    echo "=========================================="
    echo "  迅雷快鸟 OpenWrt 一键部署"
    echo "=========================================="
    echo ""

    # 默认使用之前 SSH 连接的路由器
    read -p "请输入路由器 IP 地址 [192.168.10.1]: " ROUTER_IP
    ROUTER_IP=${ROUTER_IP:-192.168.10.1}

    read -p "请输入 SSH 用户名 [root]: " SSH_USER
    SSH_USER=${SSH_USER:-root}

    read -p "请输入 SSH 端口 [22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    # 测试连接
    info "测试 SSH 连接..."
    if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER_IP" "echo 'SSH 连接成功'" 2>/dev/null; then
        error "无法连接到路由器，请检查 IP、用户名和端口"
    fi
    info "SSH 连接成功！"
}

# 安装依赖
install_dependencies() {
    echo ""
    info "检查并安装依赖包..."

    ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" << 'EOF'
        # 更新包列表
        opkg update

        # 检查并安装依赖
        for pkg in bash curl jq openssl-util; do
            if ! opkg list-installed | grep -q "^$pkg "; then
                echo "安装 $pkg..."
                opkg install "$pkg"
            else
                echo "$pkg 已安装"
            fi
        done

        # util-linux 提供 flock
        if ! command -v flock >/dev/null 2>&1; then
            echo "安装 util-linux..."
            opkg install util-linux
        fi

        echo "依赖安装完成"
EOF
}

# 部署文件
deploy_files() {
    echo ""
    info "部署文件到路由器..."

    # 创建目录
    ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" "mkdir -p /usr/share/xunlei-kuainiao /var/lib/xunlei-kuainiao /var/log/xunlei-kuainiao"

    # 复制主脚本
    info "复制主脚本..."
    scp -P "$SSH_PORT" xunlei-kuainiao-service/src/xunlei-kuainiao.sh "$SSH_USER@$ROUTER_IP:/usr/share/xunlei-kuainiao/xunlei-kuainiao.sh"

    # 复制 CLI 工具
    info "复制 CLI 工具..."
    scp -P "$SSH_PORT" xunlei-kuainiao-service/files/usr/bin/xunlei-kuainiao-cli "$SSH_USER@$ROUTER_IP:/usr/bin/xunlei-kuainiao-cli"

    # 复制配置文件
    info "复制配置文件..."
    scp -P "$SSH_PORT" xunlei-kuainiao-service/files/etc/config/xunlei-kuainiao "$SSH_USER@$ROUTER_IP:/etc/config/xunlei-kuainiao"

    # 复制 init 脚本
    info "复制 init 脚本..."
    scp -P "$SSH_PORT" xunlei-kuainiao-service/files/etc/init.d/xunlei-kuainiao "$SSH_USER@$ROUTER_IP:/etc/init.d/xunlei-kuainiao"

    # 设置权限
    info "设置文件权限..."
    ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" << 'EOF'
        chmod 755 /usr/bin/xunlei-kuainiao-cli
        chmod 755 /etc/init.d/xunlei-kuainiao
        chmod 755 /usr/share/xunlei-kuainiao/xunlei-kuainiao.sh
        chmod 600 /etc/config/xunlei-kuainiao
EOF

    info "文件部署完成！"
}

# 初始化配置
init_config() {
    echo ""
    info "初始化配置..."
    echo ""
    echo "接下来需要从浏览器获取凭据："
    echo ""
    echo "1. 在浏览器登录迅雷账号中心：https://i.xunlei.com"
    echo "2. 打开开发者工具（F12）"
    echo "3. 获取 Refresh Token："
    echo "   - Application → Local Storage → https://i.xunlei.com"
    echo "   - 找到 credentials_XW5SkOhLDjnOZP7J"
    echo "   - 复制 JSON 中的 refresh_token"
    echo ""
    echo "4. 获取 Device ID："
    echo "   - Network 标签"
    echo "   - 查找发往 xluser-ssl.xunlei.com 的请求"
    echo "   - 复制请求头中的 x-device-id"
    echo ""

    read -p "是否现在进行初始化配置？(y/n) [y]: " DO_INIT
    DO_INIT=${DO_INIT:-y}

    if [ "$DO_INIT" = "y" ] || [ "$DO_INIT" = "Y" ]; then
        echo ""
        echo "请在路由器上执行初始化命令："
        echo ""
        echo "  ssh -p $SSH_PORT $SSH_USER@$ROUTER_IP"
        echo "  xunlei-kuainiao-cli init"
        echo ""
        echo "或者在此处输入凭据，我帮您配置："
        echo ""

        read -p "请输入 Device ID: " DEVICE_ID
        read -p "请输入 Device Sign（可留空）: " DEVICE_SIGN
        read -s -p "请输入 Refresh Token: " REFRESH_TOKEN
        echo ""

        if [ -n "$DEVICE_ID" ] && [ -n "$REFRESH_TOKEN" ]; then
            # 保存到状态文件
            ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" << EOF
                mkdir -p /var/lib/xunlei-kuainiao
                cat > /var/lib/xunlei-kuainiao/state.json << 'STATEEOF'
{
    "device_id": "$DEVICE_ID",
    "account_device_sign": "$DEVICE_SIGN",
    "refresh_token": "$REFRESH_TOKEN"
}
STATEEOF
                chmod 600 /var/lib/xunlei-kuainiao/state.json
EOF

            # 保存到 UCI
            ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" << EOF
                uci set xunlei-kuainiao.main.device_id='$DEVICE_ID'
                uci set xunlei-kuainiao.main.device_sign='$DEVICE_SIGN'
                uci set xunlei-kuainiao.main.refresh_token='$REFRESH_TOKEN'
                uci commit xunlei-kuainiao
EOF

            info "凭据配置完成！"
        else
            warn "凭据不完整，请稍后手动配置"
        fi
    fi
}

# 测试运行
test_run() {
    echo ""
    read -p "是否立即测试提速？(y/n) [y]: " DO_TEST
    DO_TEST=${DO_TEST:-y}

    if [ "$DO_TEST" = "y" ] || [ "$DO_TEST" = "Y" ]; then
        info "执行提速测试..."
        ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" "xunlei-kuainiao-cli run"
    fi
}

# 启用服务
enable_service() {
    echo ""
    read -p "是否启用开机自启？(y/n) [y]: " DO_ENABLE
    DO_ENABLE=${DO_ENABLE:-y}

    if [ "$DO_ENABLE" = "y" ] || [ "$DO_ENABLE" = "Y" ]; then
        info "启用开机自启..."
        ssh -p "$SSH_PORT" "$SSH_USER@$ROUTER_IP" << 'EOF'
            /etc/init.d/xunlei-kuainiao enable
            /etc/init.d/xunlei-kuainiao start
EOF
        info "服务已启用！"
    fi
}

# 显示完成信息
show_complete() {
    echo ""
    echo "=========================================="
    echo "  部署完成！"
    echo "=========================================="
    echo ""
    echo "常用命令："
    echo ""
    echo "  # 执行提速"
    echo "  ssh -p $SSH_PORT $SSH_USER@$ROUTER_IP 'xunlei-kuainiao-cli run'"
    echo ""
    echo "  # 查看状态"
    echo "  ssh -p $SSH_PORT $SSH_USER@$ROUTER_IP 'xunlei-kuainiao-cli status'"
    echo ""
    echo "  # 查看日志"
    echo "  ssh -p $SSH_PORT $SSH_USER@$ROUTER_IP 'cat /var/log/xunlei-kuainiao/xunlei-kuainiao.log'"
    echo ""
    echo "  # LuCI Web 界面"
    echo "  http://$ROUTER_IP/cgi-bin/luci/admin/services/xunlei-kuainiao"
    echo ""
    echo "  # 重新配置凭据"
    echo "  ssh -p $SSH_PORT $SSH_USER@$ROUTER_IP 'xunlei-kuainiao-cli init'"
    echo ""
    echo "提示："
    echo "  - 需要迅雷 VIP/SVIP 账号才能使用提速功能"
    echo "  - 试用版有每日次数限制"
    echo "  - Refresh Token 会自动轮换，不要使用旧 Token"
    echo ""
}

# 主流程
main() {
    # 检查当前目录
    if [ ! -f "xunlei-kuainiao-service/src/xunlei-kuainiao.sh" ]; then
        error "请在项目根目录运行此脚本"
    fi

    get_router_info
    install_dependencies
    deploy_files
    init_config
    test_run
    enable_service
    show_complete
}

# 运行主流程
main
