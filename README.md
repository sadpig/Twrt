# Twrt (R86S 定制版 OpenWrt 固件项目)

**Twrt** 是基于官方上游 [OpenWrt `openwrt-25.12`](https://github.com/openwrt/openwrt)（Linux 6.12 LTS 内核）构建的轻量、高性能、安全加固型定制路由器固件，吸收了 **Kwrt** 的核心网络加速与实用功能，同时彻底剔除了冗余推广组件并修复了多项安全漏洞与软件包管理 Bug。

---

## 一、 核心特性（参考并优化自 Kwrt）

1. **品牌与基础网络预设**
   - **发行版标识**：`Twrt 25.12`
   - **默认管理地址**：`10.0.0.1/24`（主机名：`Twrt`，本地跳转域名：`twrt.lan` / `pw`）
   - **R86S 网口自动拓扑**：`eth0`、`eth1`、`eth2`（3× 2.5G 电口）+ `eth3`（10G SFP+）默认桥接为 `br-lan`，`eth4`（10G SFP+）默认作为 `wan` / `wan6`

2. **内核加速与转发调优**
   - 编译级 `-O2` 性能优化 + Zlib 速度优化
   - **FullCone NAT**：集成 ImmortalWrt `nftables` / `libnftnl` FullCone 表达式支持（`kmod-nft-fullcone`）
   - **流量卸载**：默认支持软件/硬件流量卸载（`kmod-nft-offload`）
   - **TCP 拥塞控制**：默认集成 `kmod-tcp-bbr` 与 `zram-swap`（`lzo-rle` / `zstd` 内存压缩）

3. **R86S 完整硬件驱动支持**
   - **有线网卡**：Intel I225/I226 2.5GbE (`kmod-igc`)、Mellanox ConnectX-3/4 万兆光口 (`kmod-mlx4-core` / `kmod-mlx5-core`)、Intel 万兆 (`kmod-ixgbe`)、Realtek 2.5G/5G (`kmod-r8125-rss` / `kmod-r8126-rss`)
   - **无线网卡**：Intel AX200 / AX201 / AX210 (`kmod-iwlwifi` + 固件 + `wpad-basic-mbedtls`)，默认开启 CN 功率表
   - **存储与传感器**：eMMC / NVMe / F2FS / EXT4 / BTRFS / NTFS3 (UTF-8) / exFAT、Intel 微码、`i915` 核显固件、CPU 调频与风扇温控 (`cpupower` / `lm-sensors` / `luci-app-fan`)

4. **精选界面与服务组件**
   - **Web 引擎**：`luci-nginx`（Nginx + SSL + uWSGI 高并发架构）
   - **主题与看板**：默认采用 `luci-theme-vantage` + `luci-app-vantage` 控制台主题（同时保留 `luci-theme-bootstrap`）
   - **核心应用**：
     - `luci-app-passwall`（`xray-core` + `sing-box` + `hysteria` + `chinadns-ng` + Nftables 透明代理）
     - `luci-app-diskman` + `luci-app-partexp`（磁盘管理与一键分区扩容）
     - `luci-app-samba4`（文件共享）
     - `luci-app-wizard` + `luci-app-advancedplus` + `luci-app-sysctl` + `luci-app-syscontrol`

---

## 二、 相比原版 Kwrt 的安全加固与精简修复

| 问题项 | 原版 Kwrt 状态 | Twrt 修复方案 |
| :--- | :--- | :--- |
| **`root` 空密码漏洞** | `passwd` 脚本失效导致 `/etc/shadow` 为空密码，任意人免密直通 | `99-twrt-security` 直接写入加密密码哈希（默认密码 `root`），杜绝空密码裸奔 |
| **FastNet 外网暴露** | 默认安装 `fastnet` 且无 Token 认证，防火墙在 WAN 口放行 TCP `3200` | 从编译源彻底剔除 `fastnet` 与 `linkease-app-entry`，并清除防火墙 `3200` 端口规则 |
| **`linkease-app-entry` 死循环** | 软件源重复打包 + 前端未过滤 `hold` 标志，更新列表永远提示升级 | 移除该冗余包，并修补 `package-manager.js` 使其严格识别 `inst.hold` 锁定标记 |
| **SSH 与 `ttyd` 监听过宽** | `dropbear` 删除了 `Interface` 监听全网，`ttyd` 绑定 `0.0.0.0:7681` | 强制 `dropbear` 仅监听 `lan`，`ttyd` 仅绑定 `@lan` 接口 |
| **Nginx 80 端口无限制** | 仅 443 配置了 `restrict_locally`，80 端口未限制 | 为 Nginx 80 端口统一加上 `restrict_locally` 内网访问限制 |
| **DNS 重绑定与 UPnP** | 关闭了 `rebind_protection`，且默认开启无 ACL 的 UPnP | 默认开启 `rebind_protection='1'`，默认关闭 UPnP 自动映射（按需在后台开启） |
| **冗余服务与推广链接** | 后台常驻闲置 `haproxy`、残留 `kulicloud`、状态页底部带推广链接 | 剔除 `haproxy` / `kulicloud` / `gpsysupgrade` / `istorex`，清理状态页底部外链 |

---

## 三、 目录结构

```text
.
├── build.sh                                # 一键拉取上游 OpenWrt、注入 Twrt 配置、编译及在线同步脚本
├── .github/workflows/build-twrt.yml        # GitHub Actions 云端自动编译工作流
├── devices/
│   ├── common/
│   │   ├── settings.ini                    # 上游 OpenWrt 仓库与分支定义 (openwrt-25.12)
│   │   ├── .config                         # Twrt 公共组件与内核特性配置
│   │   ├── diy.sh                          # 公共定制脚本 (Feeds、FullCone、品牌替换、Bug修复)
│   │   ├── patches/                        # 公共底层补丁集 (dnsmasq、nftables、luci 等)
│   │   └── diy/package/base-files/files/
│   │       ├── etc/banner                  # Twrt 终端欢迎横幅
│   │       └── etc/uci-defaults/99-twrt-security # 首次启动安全加固与品牌收口脚本
│   └── x86_64/
│       ├── .config                         # R86S / x86_64 硬件驱动与镜像配置
│       ├── diy.sh                          # x86_64 架构 -O2 优化与内核补丁脚本
│       └── patches/                        # R86S 网口自动分配 (eth0-3 LAN / eth4 WAN) 等补丁
└── kwrt-backup-2026-10-10.tar.gz           # 原始路由器配置备份归档
```

---

## 四、 使用方法

### 方式 1：在 Linux 编译机 / Docker 环境从源码编译 Twrt 固件

> 注意：OpenWrt 源码编译需要区分大小写的文件系统与 Linux 构建工具链（推荐 Ubuntu 22.04/24.04 或 Docker 容器）。

```bash
# 1. 拉取上游 OpenWrt (openwrt-25.12) 源码并注入 Twrt 定制层与补丁
./build.sh prepare

# 2. (可选) 打开菜单微调配置
./build.sh menuconfig

# 3. 开始完整编译（输出位于 openwrt/bin/targets/x86/64/）
./build.sh compile
```

### 方式 2：使用 GitHub Actions 云端一键编译

将本仓库推送到你的 GitHub 私有或公开仓库，进入 **Actions -> Build Twrt Firmware -> Run workflow**，即可免本地环境自动拉取上游 OpenWrt 源码并编译生成 `Twrt` 刷机固件（`combined-efi.img.gz`）。

### 方式 3：将 Twrt 品牌与安全加固直接应用到当前在线 R86S (`10.0.0.1`)

无需重新刷机，直接把当前正在运行的 R86S 就地转化为安全加固后的 `Twrt`：

```bash
./build.sh apply-live 10.0.0.1
```
