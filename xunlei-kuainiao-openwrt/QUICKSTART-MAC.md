# Mac 快速部署指南

无需编译环境，直接部署到路由器！

## 方法一：一键部署（推荐）

在 Mac 终端执行：

```bash
cd /path/to/xunlei-kuainiao-openwrt
./deploy.sh
```

脚本会自动：
1. 连接路由器
2. 安装依赖包
3. 部署所有文件
4. 引导您配置凭据
5. 测试提速功能

## 方法二：手动部署

### 步骤 1：安装依赖

SSH 登录路由器，安装依赖：

```bash
ssh root@192.168.10.1

opkg update
opkg install bash curl jq openssl-util util-linux
```

### 步骤 2：上传安装脚本

在 Mac 终端执行：

```bash
scp install-on-router.sh root@192.168.10.1:/tmp/
```

### 步骤 3：运行安装脚本

SSH 登录路由器执行：

```bash
ssh root@192.168.10.1
chmod +x /tmp/install-on-router.sh
/tmp/install-on-router.sh
```

### 步骤 4：初始化配置

```bash
xunlei-kuainiao-cli init
```

按提示输入：
- **x-device-id**: 从浏览器 Network 标签获取
- **x-device-sign**: 可留空
- **refresh_token**: 从浏览器 Local Storage 获取

### 步骤 5：测试提速

```bash
xunlei-kuainiao-cli run
```

### 步骤 6：启用开机自启

```bash
/etc/init.d/xunlei-kuainiao enable
/etc/init.d/xunlei-kuainiao start
```

## 获取凭据详细步骤

### 1. 获取 Refresh Token

1. 浏览器打开 https://i.xunlei.com
2. 登录迅雷账号
3. 按 F12 打开开发者工具
4. 切换到 **Application** 标签
5. 左侧找到 **Local Storage** → **https://i.xunlei.com**
6. 找到 `credentials_XW5SkOhLDjnOZP7J`
7. 复制 JSON 中的 `refresh_token` 值

### 2. 获取 Device ID

1. 在开发者工具中切换到 **Network** 标签
2. 刷新页面或执行操作
3. 找到发往 `xluser-ssl.xunlei.com` 的请求
4. 点击该请求，查看 **Headers**
5. 复制 `x-device-id` 的值

## 常用命令

```bash
# 执行提速
xunlei-kuainiao-cli run

# 查看状态
xunlei-kuainiao-cli status

# 刷新 Token
xunlei-kuainiao-cli refresh

# 查看日志
cat /var/log/xunlei-kuainiao/xunlei-kuainiao.log

# 重启服务
/etc/init.d/xunlei-kuainiao restart
```

## 故障排查

### 问题：提示"缺少依赖"
```bash
opkg update
opkg install bash curl jq openssl-util
```

### 问题：提示"试用额度已用完"
- 试用版有每日次数限制
- 等待第二天再试
- 或升级迅雷 VIP/SVIP

### 问题：Token 失效
```bash
xunlei-kuainiao-cli init
# 重新输入凭据
```

### 问题：查看详细日志
```bash
# 启用调试模式
XL_DEBUG=1 xunlei-kuainiao-cli run

# 查看调试文件
ls -la /var/log/xunlei-kuainiao/debug/
```

## 注意事项

1. 需要迅雷 VIP/SVIP 账号才能使用提速功能
2. 试用版有每日次数限制（ret=11 表示已用完）
3. Refresh Token 会自动轮换，不要使用旧 Token
4. 接口可能随时变更，请关注项目更新
