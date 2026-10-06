# 迅雷快鸟 OpenWrt 提速插件

基于 OAuth/PKCE 流程的迅雷快鸟宽带提速服务 OpenWrt 实现。

## 功能特性

- ✅ 支持迅雷新版 OAuth/PKCE 认证流程
- ✅ 纯 Shell 实现，无需 Python
- ✅ LuCI Web 管理界面
- ✅ 自动续期（cron 定时任务）
- ✅ 状态查询和日志记录
- ✅ UCI 配置支持

## 系统要求

- OpenWrt 21.02 或更高版本
- 迅雷 VIP/SVIP 账号
- 依赖包：`bash`, `curl`, `jq`, `openssl`, `util-linux`

## 安装方法

### 方法一：编译 ipk 包

1. 克隆本项目到 OpenWrt SDK 的 `package/` 目录：
```bash
cd /path/to/openwrt-sdk/package
git clone https://github.com/your-repo/xunlei-kuainiao-openwrt.git
```

2. 更新 feeds 并选择包：
```bash
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
# 选择 LuCI -> Applications -> luci-app-xunleikuainiao
```

3. 编译：
```bash
make package/xunlei-kuainiao-service/compile V=s
make package/luci-app-xunleikuainiao/compile V=s
```

4. 生成的 ipk 文件在：
```
bin/packages/mipsel_24kc/base/xunlei-kuainiao-service_*.ipk
bin/packages/mipsel_24kc/luci/luci-app-xunleikuainiao_*.ipk
```

### 方法二：手动安装

1. 安装依赖：
```bash
opkg update
opkg install bash curl jq openssl util-linux
```

2. 复制文件到路由器：
```bash
# 复制主脚本
scp xunlei-kuainiao-service/src/xunlei-kuainiao.sh root@路由器IP:/usr/share/xunlei-kuainiao/

# 复制 CLI 工具
scp xunlei-kuainiao-service/files/usr/bin/xunlei-kuainiao-cli root@路由器IP:/usr/bin/

# 复制配置文件
scp xunlei-kuainiao-service/files/etc/config/xunlei-kuainiao root@路由器IP:/etc/config/

# 复制 init 脚本
scp xunlei-kuainiao-service/files/etc/init.d/xunlei-kuainiao root@路由器IP:/etc/init.d/

# 设置权限
ssh root@路由器IP "chmod 755 /usr/bin/xunlei-kuainiao-cli /etc/init.d/xunlei-kuainiao /usr/share/xunlei-kuainiao/xunlei-kuainiao.sh"
```

## 使用方法

### 首次配置

1. **获取凭据**（一次性操作）：

   a. 在浏览器登录迅雷账号中心：https://i.xunlei.com
   
   b. 打开开发者工具（F12）
   
   c. 获取 Refresh Token：
      - 进入 Application → Local Storage → `https://i.xunlei.com`
      - 找到 `credentials_XW5SkOhLDjnOZP7J`
      - 复制 JSON 中的 `refresh_token`
   
   d. 获取 Device ID：
      - 进入 Network 标签
      - 查找发往 `xluser-ssl.xunlei.com` 的请求
      - 复制请求头中的 `x-device-id`

2. **初始化配置**：
```bash
xunlei-kuainiao-cli init
```

   按提示输入：
   - x-device-id
   - x-device-sign（可留空）
   - refresh_token

### 命令行使用

```bash
# 执行完整提速流程
xunlei-kuainiao-cli run

# 查看当前状态
xunlei-kuainiao-cli status

# 只刷新 Token
xunlei-kuainiao-cli refresh

# 查看帮助
xunlei-kuainiao-cli help
```

### LuCI Web 界面

访问路由器管理界面：`http://路由器IP/cgi-bin/luci/admin/services/xunlei-kuainiao`

功能：
- 配置凭据（Device ID、Refresh Token）
- 启用/禁用服务
- 设置自动续期 cron 任务
- 查看服务状态

### 服务管理

```bash
# 启动服务
/etc/init.d/xunlei-kuainiao start

# 停止服务
/etc/init.d/xunlei-kuainiao stop

# 重启服务
/etc/init.d/xunlei-kuainiao restart

# 查看状态
/etc/init.d/xunlei-kuainiao status

# 启用开机自启
/etc/init.d/xunlei-kuainiao enable
```

## 配置文件说明

### UCI 配置 (`/etc/config/xunlei-kuainiao`)

```uci
config xunlei-kuainiao 'main'
    option enabled '1'              # 启用服务
    option device_id ''             # Device ID
    option refresh_token ''         # Refresh Token
    option device_sign ''           # Device Sign（可选）
    option auto_renew '1'           # 启用自动续期
    option renew_cron '15 3 * * *'  # Cron 表达式
    option log_level 'info'         # 日志级别
    option state_file '/var/lib/xunlei-kuainiao/state.json'
```

## 文件位置

| 文件 | 说明 |
|------|------|
| `/usr/share/xunlei-kuainiao/xunlei-kuainiao.sh` | 主脚本 |
| `/usr/bin/xunlei-kuainiao-cli` | CLI 包装脚本 |
| `/etc/config/xunlei-kuainiao` | UCI 配置文件 |
| `/etc/init.d/xunlei-kuainiao` | 服务 init 脚本 |
| `/var/lib/xunlei-kuainiao/state.json` | 状态文件 |
| `/var/log/xunlei-kuainiao/xunlei-kuainiao.log` | 日志文件 |
| `/var/log/xunlei-kuainiao/debug/` | 调试响应（需 XL_DEBUG=1）|

## 调试

启用调试模式保存各步骤响应：
```bash
XL_DEBUG=1 xunlei-kuainiao-cli run
```

调试文件保存在：`/var/log/xunlei-kuainiao/debug/`

## 常见问题

### Q: 提示"缺少依赖"怎么办？
A: 安装所需依赖：
```bash
opkg install bash curl jq openssl util-linux
```

### Q: 提示"试用额度已用完"（ret=11）怎么办？
A: 试用版有每日次数限制，请明天再试，或升级迅雷 VIP/SVIP。

### Q: Refresh Token 失效了怎么办？
A: Refresh Token 会自动轮换，请勿手动使用旧 Token。如果完全失效，需要重新获取凭据并执行 `init`。

### Q: 如何查看详细日志？
A: 查看日志文件：
```bash
cat /var/log/xunlei-kuainiao/xunlei-kuainiao.log
```

### Q: OpenWrt 默认 shell 不支持脚本怎么办？
A: 需要安装 bash：
```bash
opkg install bash
```

## 技术说明

### 认证流程

```
1. 刷新账号中心 Token
   refresh_token → account_access_token

2. 生成 PKCE 参数
   code_verifier + code_challenge

3. 获取 OAuth 授权码
   account_access_token → authorization_code

4. 兑换快鸟 Token
   authorization_code → speedup_access_token

5. 调用提速开通
   speedup_access_token → 提速成功
```

### API 端点

- 账号中心 Token: `https://xluser-ssl.xunlei.com/v1/auth/token`
- OAuth 授权: `https://xluser-ssl.xunlei.com/v1/user/authorize`
- 提速开通: `https://speedup.xunlei.com/v1/open`

## 参考项目

- [Sakamakiiizayoi/xunlei-speedup-oauth](https://github.com/Sakamakiiizayoi/xunlei-speedup-oauth) - 主要参考
- [fffonion/Xunlei-Fastdick](https://github.com/fffonion/Xunlei-Fastdick) - 历史参考（已失效）

## 免责声明

- 本项目为非官方实现，接口可能随时变更
- 请仅用于自己的迅雷账号和宽带线路
- 请遵守迅雷相关服务条款
- 使用本项目造成的任何问题，作者不承担责任

## 许可证

MIT License
