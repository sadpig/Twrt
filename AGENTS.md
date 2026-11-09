# AGENTS.md

## 项目定位

本目录是 **Twrt** 定制路由器固件项目（目标设备：**R86S**，`x86_64` 架构，LAN IP `10.0.0.1`）。
基于官方上游 OpenWrt (`openwrt-25.12`) 源码构建，参考并保留了 Kwrt 的核心性能与实用插件特性（FullCone NAT、流量卸载、BBR、Nginx+LuCI、Vantage 主题、PassWall、DiskMan、PartExp 等），同时内置安全加固与精简修复。

## 关键文件说明

- `build.sh`：核心构建与在线同步脚本（支持 `clone`、`prepare`、`menuconfig`、`compile`、`all`、`apply-live`）。
- `devices/common/`：Twrt 通用定制层（包含 `settings.ini`、`.config`、`diy.sh`、`patches/` 以及 `diy/package/base-files/files/etc/uci-defaults/99-twrt-security`）。
- `devices/x86_64/`：R86S (`x86_64`) 硬件驱动配置、`-O2` 编译优化及 5 网口自动分配补丁（`eth0-eth3` 为 `br-lan`，`eth4` 为 `wan`）。
- `.github/workflows/build-twrt.yml`：GitHub Actions 云端编译工作流。

## 维护规范

- 所有脚本改动后需通过 `bash -n build.sh devices/common/diy.sh devices/x86_64/diy.sh` 和 `sh -n devices/common/diy/package/base-files/files/etc/uci-defaults/99-twrt-security` 语法检查。
- 涉及在线路由器（`10.0.0.1`）的操作，请勿在输出中打印 Wi-Fi 密钥或代理节点敏感凭据。
