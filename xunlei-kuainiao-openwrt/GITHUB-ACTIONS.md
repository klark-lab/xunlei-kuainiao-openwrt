# GitHub Actions 自动编译指南

使用 GitHub Actions 自动编译 OpenWrt ipk 包，无需本地编译环境！

## 快速开始

### 1. Fork 项目

点击右上角 **Fork** 按钮，将项目复制到您的 GitHub 账号

### 2. 启用 Actions

1. 进入您 Fork 的项目
2. 点击 **Actions** 标签
3. 点击 **I understand my workflows, go ahead and enable them**

### 3. 触发编译

#### 方式一：自动触发
- 推送代码到 `main` 分支会自动触发编译
- 提交 Pull Request 也会触发编译

#### 方式二：手动触发
1. 进入 **Actions** 标签
2. 选择 **Build OpenWrt Packages** 工作流
3. 点击 **Run workflow**
4. 选择参数：
   - **OpenWrt Version**: 默认 23.05.3
   - **Target Architecture**: 选择架构或 all
5. 点击 **Run workflow** 按钮

### 4. 下载编译结果

1. 编译完成后，进入 **Actions** 标签
2. 点击最新的编译任务
3. 在 **Artifacts** 部分下载对应架构的 ipk 包
4. 解压后得到 `.ipk` 文件

## 支持的架构

| 架构 | 目标平台 | 典型设备 |
|------|----------|----------|
| `mipsel_24kc` | ramips/mt7621 | 大多数路由器（如 Newifi、竞斗云等）|
| `aarch64_generic` | rockchip/armv8 | ARM64 设备（如 R2S、R4S）|
| `x86_64` | x86/64 | x86 软路由 |

## 工作流说明

### build-openwrt.yml
- **触发条件**: push、PR、手动触发
- **编译架构**: 支持多架构（mipsel_24kc、aarch64_generic、x86_64）
- **产物**: 每个架构单独的 ipk 包
- **发布**: 推送到 main 分支时自动创建 Release

### build-mips.yml
- **触发条件**: push、PR、手动触发
- **编译架构**: 仅 MIPS（mipsel_24kc）
- **产物**: MIPS 架构的 ipk 包
- **用途**: 快速编译 MIPS 包

## 安装编译好的包

### 方法一：通过 LuCI 界面

1. 登录路由器管理界面
2. 进入 **系统** → **软件包**
3. 点击 **上传软件包**
4. 上传下载的 `.ipk` 文件
5. 点击 **安装**

### 方法二：通过命令行

```bash
# 上传包到路由器
scp xunlei-kuainiao-service_*.ipk root@192.168.10.1:/tmp/
scp luci-app-xunleikuainiao_*.ipk root@192.168.10.1:/tmp/

# SSH 登录路由器
ssh root@192.168.10.1

# 安装依赖
opkg update
opkg install bash curl jq openssl-util util-linux

# 安装包
cd /tmp
opkg install xunlei-kuainiao-service_*.ipk
opkg install luci-app-xunleikuainiao_*.ipk

# 初始化配置
xunlei-kuainiao-cli init

# 启用服务
/etc/init.d/xunlei-kuainiao enable
/etc/init.d/xunlei-kuainiao start
```

## 自定义编译

### 修改 OpenWrt 版本

编辑 `.github/workflows/build-openwrt.yml`：

```yaml
env:
  OPENWRT_VERSION: '23.05.3'  # 修改为其他版本
```

### 添加其他架构

在 `build-openwrt.yml` 的 `matrix.include` 中添加：

```yaml
- arch: your_arch
  target: your_target
  subtarget: your_subtarget
  sdk_url: https://downloads.openwrt.org/releases/YOUR_VERSION/targets/YOUR_TARGET/YOUR_SUBTARGET/openwrt-sdk-YOUR_VERSION-*.tar.xz
```

### 修改 SDK 下载地址

如果默认下载地址失效，可以在 OpenWrt 官网找到最新的 SDK：

- 官网: https://downloads.openwrt.org/releases/
- 路径: `releases/版本/targets/目标/子目标/`

## 常见问题

### Q: 编译失败怎么办？
A: 查看 Actions 日志，常见原因：
- SDK 下载失败（网络问题）
- 依赖包安装失败
- 代码语法错误

### Q: 如何获取最新的 SDK 地址？
A: 访问 https://downloads.openwrt.org/releases/ 找到对应版本和架构的 SDK

### Q: 编译的包能在其他 OpenWrt 版本使用吗？
A: 建议使用相同版本的 SDK 编译，不同版本可能存在兼容性问题

### Q: 如何添加自定义功能？
A: 修改源码后推送到 main 分支，Actions 会自动重新编译

## 高级配置

### 使用 Secrets

如果需要访问私有资源，可以在 GitHub 项目设置中添加 Secrets：

1. 进入项目 **Settings** → **Secrets and variables** → **Actions**
2. 点击 **New repository secret**
3. 添加需要的密钥

### 定时编译

在工作流中添加定时触发：

```yaml
on:
  schedule:
    - cron: '0 0 * * 0'  # 每周日 UTC 0:00
```

### 缓存优化

添加缓存减少编译时间：

```yaml
- name: Cache SDK
  uses: actions/cache@v3
  with:
    path: openwrt-sdk
    key: openwrt-sdk-${{ matrix.arch }}-${{ env.OPENWRT_VERSION }}
```

## 相关链接

- [OpenWrt 官网](https://openwrt.org/)
- [OpenWrt SDK 下载](https://downloads.openwrt.org/releases/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [迅雷快鸟官网](https://k.xunlei.com)
