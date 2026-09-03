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
