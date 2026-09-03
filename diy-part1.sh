#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# Upstream feeds.conf.default already ships helloworld (line 8). Appending it
# unconditionally creates a duplicate entry and ./scripts/feeds update -a aborts:
#   Duplicate feed name 'helloworld' in 'feeds.conf.default' line: 14
# So only add it when it is genuinely missing.
grep -qE '^src-git[[:space:]]+helloworld[[:space:]]' feeds.conf.default \
  || echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
