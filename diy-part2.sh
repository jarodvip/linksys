#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# 移除 IEI WT61P803 PUZZLE 系列内核补丁（mvebu 9xx）
#
# 故障现象（2026-09-04 的 Actions 运行 33782809257 在 "Compile the firmware" 失败）：
#   Applying .../mvebu/patches-6.6/902-drivers-mfd-Add-a-driver-for-IEI-WT61P803-PUZZLE-MCU.patch
#   The next patch would create the file drivers/mfd/iei-wt61p803-puzzle.c,
#   which already exists!  Applying it anyway.
#   Hunk #1 FAILED at 1.
#   Patch failed!  Please fix .../902-....patch!
#   make[4]: *** ... Error 1  ->  ERROR: target/linux failed to build.
#
# 根因：9xx 这组补丁是把 Linux 6.7 才合入上游的 IEI WT61P803 PUZZLE MCU/HWMON/LED
# 驱动反向移植到 6.6 内核的。而构建锁定的 linux-6.6.155 源码树里这些文件已经存在，
# 于是"新建文件"型补丁全部失败，target/linux 直接中断。
# 该组补丁服务的设备是 IEI WT61P803 PUZZLE（Marvell Armada 8040 / cortexa72），
# 与本项目目标 WRT1900AC V2（Marvell Armada 385 / cortexa9）无关，删除无副作用。
#
# 对 6.6 / 6.12 / 6.18 三个补丁目录一并处理，避免日后切换内核版本时再次踩坑。
# ---------------------------------------------------------------------------
for patches_dir in target/linux/mvebu/patches-*; do
  [ -d "$patches_dir" ] || continue
  rm -f "$patches_dir"/9[0-9][0-9]-*IEI*.patch \
        "$patches_dir"/9[0-9][0-9]-*wt61p803*.patch \
        "$patches_dir"/9[0-9][0-9]-*puzzle*.patch
done

# ---------------------------------------------------------------------------
# 防御性修复：kmod-cfg80211 对 wifi-scripts 的悬空依赖
#
# 上游曾让 package/kernel/mac80211/Makefile 里的 kmod-cfg80211 硬依赖一个源码树中
# 并不存在的 wifi-scripts 包。该依赖在 Install feeds 阶段只是 WARNING，但要等到
# 约 1 小时后的 rootfs 组装阶段才 fatal：
#   pkg_hash_check_unresolved: cannot find dependency 'wifi-scripts' for kmod-cfg80211
# 上游已修掉，这里保留兜底，防止回归。
# ---------------------------------------------------------------------------
if grep -q 'wifi-scripts' package/kernel/mac80211/Makefile 2>/dev/null; then
  sed -i 's/ +wifi-scripts//g' package/kernel/mac80211/Makefile
fi

# 网络性能调优：增大 TCP 缓冲区、扩容 conntrack
grep -q 'net.core.rmem_max' package/base-files/files/etc/sysctl.conf 2>/dev/null || cat >> package/base-files/files/etc/sysctl.conf << 'EOF'

# TCP 缓冲区扩容（提升大文件传输/下载吞吐）
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# conntrack 表扩容（代理场景连接数激增）
net.nf_conntrack_max=65535
net.netfilter.nf_conntrack_max=65535
EOF
