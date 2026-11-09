#!/usr/bin/env bash
#====================================================================
# Twrt 固件构建与管理脚本 (基于上游 OpenWrt 25.12 + Kwrt 核心特性)
# 用法:
#   ./build.sh clone       # 拉取上游 OpenWrt 源码 (openwrt-25.12)
#   ./build.sh prepare     # 注入 Twrt 配置、Feeds、补丁并执行 make defconfig
#   ./build.sh menuconfig  # 打开交互式配置菜单
#   ./build.sh compile        # 编译生成 Twrt 固件镜像
#   ./build.sh all            # 一键执行 clone -> prepare -> compile
#   ./build.sh apply-live     # 将 Twrt 品牌标识与安全加固直接应用到在线 R86S (10.0.0.1)
#   ./build.sh upgrade-router # 将本地编译好的 Twrt 固件上传并保留配置刷入 R86S (10.0.0.1)
#   ./build.sh ota            # 从 GitHub (sadpig/Twrt) 拉取最新云端编译固件并刷入 R86S (10.0.0.1)
#====================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-x86_64}"
OPENWRT_DIR="${OPENWRT_DIR:-${ROOT_DIR}/openwrt}"

source "${ROOT_DIR}/devices/common/settings.ini"
if [ -f "${ROOT_DIR}/devices/${TARGET}/settings.ini" ]; then
	source "${ROOT_DIR}/devices/${TARGET}/settings.ini"
fi

git_clone_path() {
	local branch="$1" rurl="$2" mv_flag="$3"
	if [ "$mv_flag" != "mv" ]; then
		shift 2
	else
		shift 3
	fi
	local rootdir="$PWD"
	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' RETURN

	if [ "${#branch}" -lt 10 ]; then
		git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$rurl" "$tmpdir"
		cd "$tmpdir"
	else
		git clone --filter=blob:none --sparse "$rurl" "$tmpdir"
		cd "$tmpdir"
		git checkout "$branch"
	fi
	git sparse-checkout init --cone
	git sparse-checkout set "$@"
	if [ "$mv_flag" != "mv" ]; then
		cp -rn ./* "$rootdir/"
	else
		mv -n "$@"/* "$rootdir/$@/"
	fi
	cd "$rootdir"
}
export -f git_clone_path

cmd_clone() {
	echo "==> [1/3] 正在从上游拉取 OpenWrt 源码 (${REPO_URL} @ ${REPO_BRANCH})..."
	if [ -d "${OPENWRT_DIR}/.git" ]; then
		echo "==> 检测到已有源码目录 ${OPENWRT_DIR}，正在同步更新..."
		git -C "${OPENWRT_DIR}" fetch origin "${REPO_BRANCH}"
		git -C "${OPENWRT_DIR}" reset --hard "origin/${REPO_BRANCH}"
	else
		git clone --depth 1 -b "${REPO_BRANCH}" "${REPO_URL}" "${OPENWRT_DIR}"
	fi
}

cmd_prepare() {
	if [ ! -d "${OPENWRT_DIR}/.git" ]; then
		cmd_clone
	fi

	echo "==> [2/3] 正在注入 Twrt (${TARGET}) 定制配置、Feeds 与补丁..."
	cp -rf "${ROOT_DIR}/devices/common/." "${OPENWRT_DIR}/"
	cp -rf "${ROOT_DIR}/devices/${TARGET}/." "${OPENWRT_DIR}/"
	cp -rf "${ROOT_DIR}/devices" "${OPENWRT_DIR}/"

	cd "${OPENWRT_DIR}"
	chmod +x "devices/common/${DIY_SH}"
	/bin/bash "devices/common/${DIY_SH}"

	cp -f "devices/common/${CONFIG_FILE}" .config
	if [ -f "devices/${TARGET}/${CONFIG_FILE}" ]; then
		echo >> .config
		cat "devices/${TARGET}/${CONFIG_FILE}" >> .config
	fi

	if [ -f "devices/${TARGET}/${DIY_SH}" ]; then
		chmod +x "devices/${TARGET}/${DIY_SH}"
		/bin/bash "devices/${TARGET}/${DIY_SH}"
	fi

	cp -Rf ./diy/* ./ 2>/dev/null || true

	cp -rn devices/common/patches "devices/${TARGET}/" 2>/dev/null || true
	find "devices/${TARGET}/patches" -maxdepth 1 -type f -name '*.revert.patch' -print0 2>/dev/null | sort -z | xargs -I % -t -0 -n 1 sh -c "patch -d './' -R --no-backup-if-mismatch -p1 -F 1 -i '%'" || true
	find "devices/${TARGET}/patches" -maxdepth 1 -type f -name '*.patch' ! -name '*.revert.patch' ! -name '*.bin.patch' -print0 2>/dev/null | sort -z | xargs -I % -t -0 -n 1 sh -c "patch -d './' --no-backup-if-mismatch -p1 -F 1 -i '%'" || true

	make defconfig
	echo "==> Twrt (${TARGET}) 配置准备完成！配置文件位于: ${OPENWRT_DIR}/.config"
}

cmd_compile() {
	cd "${OPENWRT_DIR}"
	local jobs
	jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
	echo "==> [3/3] 开始编译 Twrt (${TARGET})，并行线程数: ${jobs}..."
	make download -j8
	make -j"${jobs}" || make -j1 V=s
	echo "==> 编译完成！固件输出目录: ${OPENWRT_DIR}/bin/targets/"
}

cmd_apply_live() {
	local router_ip="${1:-10.0.0.1}"
	local router_pass="${ROUTER_PASS:-root}"
	echo "==> 正在将 Twrt 品牌与安全加固配置直接同步到在线路由器 root@${router_ip} ..."
	sshpass -p "${router_pass}" scp -o StrictHostKeyChecking=accept-new \
		"${ROOT_DIR}/devices/common/diy/package/base-files/files/etc/banner" \
		"root@${router_ip}:/etc/banner"
	sshpass -p "${router_pass}" scp -o StrictHostKeyChecking=accept-new \
		"${ROOT_DIR}/devices/common/diy/package/base-files/files/usr/sbin/twrt-upgrade" \
		"root@${router_ip}:/usr/sbin/twrt-upgrade"
	sshpass -p "${router_pass}" scp -o StrictHostKeyChecking=accept-new \
		"${ROOT_DIR}/devices/common/diy/package/base-files/files/etc/uci-defaults/99-twrt-security" \
		"root@${router_ip}:/tmp/99-twrt-security"
	sshpass -p "${router_pass}" ssh -o StrictHostKeyChecking=accept-new "root@${router_ip}" '
		chmod +x /usr/sbin/twrt-upgrade
		sh /tmp/99-twrt-security
		rm -f /tmp/99-twrt-security
		sed -i "s/Kwrt/Twrt/g; s/kwrt/twrt/g; s/Kiddin\x27/Twrt/g" /etc/openwrt_release /etc/os-release /usr/lib/os-release /etc/device_info /etc/banner 2>/dev/null || true
		sed -i "s/menuentry \"Kwrt/menuentry \"Twrt/g" /boot/grub/grub.cfg 2>/dev/null || true
		sed -i "/openwrt\.ai/d; /kiddin9\/Kwrt/d; /t\.me\/opkwrt/d" /www/luci-static/resources/view/status/include/10_system.js 2>/dev/null || true
		/etc/init.d/system reload 2>/dev/null || true
		/etc/init.d/dropbear reload 2>/dev/null || true
		/etc/init.d/nginx reload 2>/dev/null || true
		/etc/init.d/dnsmasq reload 2>/dev/null || true
		/etc/init.d/firewall reload 2>/dev/null || true
	'
	echo "==> 在线路由器 ${router_ip} 已成功升级为 Twrt 并完成安全加固！"
}

cmd_upgrade_router() {
	local router_ip="${1:-10.0.0.1}"
	local img_file="${2:-}"
	local router_pass="${ROUTER_PASS:-root}"

	if [ -z "${img_file}" ]; then
		img_file="$(find "${OPENWRT_DIR}/bin/targets" -type f -name "*-combined-efi.img.gz" 2>/dev/null | head -n 1 || true)"
	fi

	if [ -z "${img_file}" ] || [ ! -f "${img_file}" ]; then
		echo "错误: 未找到可刷写的固件文件 (*-combined-efi.img.gz)，请先编译或指定固件路径：" >&2
		echo "  $0 upgrade-router 10.0.0.1 /path/to/twrt-x86-64-generic-squashfs-combined-efi.img.gz" >&2
		exit 1
	fi

	echo "==> 准备上传固件 $(basename "${img_file}") 到 root@${router_ip}:/tmp/firmware.img.gz ..."
	sshpass -p "${router_pass}" scp -o StrictHostKeyChecking=accept-new "${img_file}" "root@${router_ip}:/tmp/firmware.img.gz"
	echo "==> 正在校验固件..."
	sshpass -p "${router_pass}" ssh -o StrictHostKeyChecking=accept-new "root@${router_ip}" "sysupgrade --test /tmp/firmware.img.gz"
	echo "==> 校验通过，开始执行保留配置升级 (sysupgrade -v /tmp/firmware.img.gz)..."
	sshpass -p "${router_pass}" ssh -o StrictHostKeyChecking=accept-new "root@${router_ip}" "sysupgrade -v /tmp/firmware.img.gz" || true
	echo "==> 路由器正在重启并完成升级，请等待约 60 秒后重连 ${router_ip}。"
}

cmd_ota() {
	local router_ip="${1:-10.0.0.1}"
	echo "==> 正在从 GitHub (sadpig/Twrt) 获取最新 Release 固件..."
	local tmp_img
	tmp_img="$(mktemp -t twrt-efi).img.gz"
	gh release download --repo sadpig/Twrt --pattern "*-combined-efi.img.gz" --output "${tmp_img}" --clobber
	cmd_upgrade_router "${router_ip}" "${tmp_img}"
	rm -f "${tmp_img}"
}

case "${1:-help}" in
	clone)          cmd_clone ;;
	prepare)        cmd_prepare ;;
	menuconfig)     cd "${OPENWRT_DIR}" && make menuconfig ;;
	compile)        cmd_compile ;;
	all)            cmd_clone && cmd_prepare && cmd_compile ;;
	apply-live)     cmd_apply_live "${2:-10.0.0.1}" ;;
	upgrade-router) cmd_upgrade_router "${2:-10.0.0.1}" "${3:-}" ;;
	ota)            cmd_ota "${2:-10.0.0.1}" ;;
	*)
		echo "用法: $0 {clone|prepare|menuconfig|compile|all|apply-live [IP]|upgrade-router [IP] [IMG_PATH]|ota [IP]}"
		exit 1
		;;
esac
