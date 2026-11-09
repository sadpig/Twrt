#!/bin/bash
#=================================================
# Twrt 公共定制脚本 (基于 OpenWrt 25.12 + Kwrt 核心特性 + 安全加固)
#=================================================
shopt -s extglob

# 1. 配置软件源 Feeds (引入 kiddin9 插件库并切回 GitHub 官方源)
sed -i '$a src-git kiddin9 https://github.com/kiddin9/op-packages.git;main' feeds.conf.default
sed -i "/telephony/d" feeds.conf.default
sed -i "s?targets/%S/packages?targets/%S/\$(LINUX_VERSION)?" include/feeds.mk
sed -i '/	refresh_config();/d' scripts/feeds
sed -i "s?git.openwrt.org/\(project\|feed\)?github.com/openwrt?g" feeds.conf.default

./scripts/feeds update -a

# 移除存在严重安全隐患、重复版本死循环或捆绑推广的冗余包
rm -rf feeds/kiddin9/{fastnet,luci-app-fastnet,app-meta-fastnet,linkease-app-entry,luci-app-kulicloud,luci-app-gpsysupgrade,luci-app-istorex,luci-app-store,quickstart,luci-app-quickstart}

./scripts/feeds install -a -p kiddin9 -f
./scripts/feeds install -a

# 2. Twrt 版本与品牌定义 (替换默认 IP 为 10.0.0.1，系统标识改为 Twrt)
date_rev="$(date +%m.%d.%Y)"
sed --follow-symlinks -i "s#%C\"#%C by Twrt\"#" package/base-files/files/etc/os-release
sed -i -e '$a /etc/bench.log' \
        -e '/\/etc\/profile/d' \
        -e '/\/etc\/shinit/d' \
        package/base-files/files/lib/upgrade/keep.d/base-files-essential
sed -i -e '/^\/etc\/profile/d' \
        -e '/^\/etc\/shinit/d' \
        package/base-files/Makefile
sed -i "s/192.168.1/10.0.0/" package/base-files/files/bin/config_generate
sed -i "s#false; \\\#true; \\\#" include/download.mk

# 3. 引入 ImmortalWrt / LEDE 核心增强特性 (FullCone NAT、NTFS3 UTF-8、无线功率解锁)
wget -N https://github.com/immortalwrt/immortalwrt/raw/refs/heads/openwrt-25.12/package/kernel/linux/modules/video.mk -P package/kernel/linux/modules/
wget -N https://github.com/immortalwrt/immortalwrt/raw/refs/heads/openwrt-25.12/package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch -P package/network/utils/nftables/patches/
wget -N https://github.com/immortalwrt/immortalwrt/raw/refs/heads/openwrt-25.12/package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch -P package/libs/libnftnl/patches/
wget -N https://github.com/immortalwrt/immortalwrt/raw/refs/heads/openwrt-25.12/package/firmware/wireless-regdb/patches/600-custom-change-txpower-and-dfs.patch -P package/firmware/wireless-regdb/patches/
wget -N https://github.com/coolsnowwolf/lede/raw/refs/heads/master/package/system/fstools/patches/0200-ntfs3-with-utf8.patch -P package/system/fstools/patches/
wget -N https://github.com/immortalwrt/immortalwrt/raw/refs/heads/openwrt-25.12/config/Config-kernel.in -P config/

rm -rf package/libs/openssl package/network/services/ppp
git_clone_path openwrt-25.12 https://github.com/immortalwrt/immortalwrt package/libs/openssl package/network/services/ppp

# 4. 默认基础软件包集合 (参考 Kwrt 核心功能，剔除冗余推广插件)
echo "$(date +"%s")" >version.date
sed -i '/$(curdir)\/compile:/c\$(curdir)/compile: package/opkg/host/compile' package/Makefile
sed -i "s/DEFAULT_PACKAGES:=/DEFAULT_PACKAGES:=luci-app-advancedplus luci-app-sysctl luci-app-firewall luci-app-package-manager luci-app-upnp luci-app-syscontrol \
luci-app-wizard luci-base luci-compat luci-lib-ipkg luci-lib-fs \
coremark wget-ssl curl autocore htop nano zram-swap kmod-lib-zstd kmod-tcp-bbr bash openssh-sftp-server block-mount resolveip ds-lite swconfig luci-app-fan luci-app-footstrap-files luci-app-wifihistory /" include/target.mk

sed -i "s/^.*vermagic$/\techo '1' > \$(LINUX_DIR)\/.vermagic/" include/kernel-defaults.mk

wget -N https://raw.githubusercontent.com/openwrt/packages/master/lang/golang/golang/Makefile -P feeds/packages/lang/golang/golang/

git_clone_path master https://github.com/coolsnowwolf/lede mv target/linux/generic/hack-6.12
wget -N https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/generic/pending-6.12/613-netfilter_optional_tcp_window_check.patch -P target/linux/generic/pending-6.12/

sed -i 's/max_requests 3/max_requests 20/g' package/network/services/uhttpd/files/uhttpd.config
sed -i "s/tty\(0\|1\)::askfirst/tty\1::respawn/g" target/linux/*/base-files/etc/inittab

sed -i -e "/\(# \)\?REVISION:=/c\REVISION:=$date_rev" -e '/VERSION_CODE:=/c\VERSION_CODE:=$(REVISION)' include/version.mk
sed -i 's/option timeout 30/option timeout 120/g' package/system/rpcd/files/rpcd.config

sed -i \
	-e "s/+\(luci\|luci-ssl\|uhttpd\)\( \|$\)/\2/" \
	-e "s/+nginx\( \|$\)/+nginx-ssl\1/" \
	-e 's/+python\( \|$\)/+python3/' \
	-e 's?../../lang?$(TOPDIR)/feeds/packages/lang?' \
	package/feeds/kiddin9/*/Makefile 2>/dev/null || true

# 5. 全局品牌重塑为 Twrt
sed -i "s/OpenWrt/Twrt/g" package/base-files/files/bin/config_generate package/base-files/image-config.in package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc config/Config-images.in Config.in include/u-boot.mk include/version.mk || true
sed -i "s/Kwrt/Twrt/g; s/kwrt/twrt/g" package/feeds/kiddin9/my-default-settings/files/etc/uci-defaults/99-default-settings 2>/dev/null || true
sed -i "s/Kwrt/Twrt/g; s/kwrt\.lan/twrt.lan/g" package/feeds/kiddin9/luci-app-wizard/htdocs/luci-static/resources/view/wizard/initsetup.js 2>/dev/null || true

# 移除状态页底部的 Kwrt 推广外链 (固件下载/赞助/TG群)
find feeds/ package/ -name "10_system.js" -exec sed -i '/openwrt\.ai/d; /kiddin9\/Kwrt/d; /t\.me\/opkwrt/d' {} + 2>/dev/null || true

# 6. 修复 luci-app-package-manager 忽略 hold 锁定包状态的 Bug
find feeds/ package/ -name "package-manager.js" -exec sed -i \
	-e "s/if (!isPkgInstalled(inst) || pkg\.name\.includes('busybox')/if (!isPkgInstalled(inst) || inst.hold || pkg.name.includes('busybox')/" \
	-e "s/else if (isPkgInstalled(inst) && compareVersion(pkg\.version, inst\.version) > 0)/else if (isPkgInstalled(inst) \&\& !inst.hold \&\& compareVersion(pkg.version, inst.version) > 0)/" \
	{} + 2>/dev/null || true

# 7. 默认 Wi-Fi 国家码设为 CN 并默认启用
sed -i -e "s/set \${s}.country='\${country || ''}'/set \${s}.country='\${country || \"CN\"}'/g" -e "s/set \${s}.disabled=.*/set \${s}.disabled='0'/" package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc

chmod +x package/base-files/files/etc/uci-defaults/* package/base-files/files/usr/sbin/* 2>/dev/null || true
rm -rf package/feeds/packages/jool package/feeds/routing/batman-adv
