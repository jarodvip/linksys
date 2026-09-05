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

# ---------------------------------------------------------------------------
# 防御性修复：fw3(firewall) 对 iptables-mod-fullconenat 的硬依赖缺源
#
# 已核实（2026-09-05，逐 feed 全树比对）：lede master 的 firewall Makefile
# 硬依赖 iptables-mod-fullconenat，但该包与内核模块 kmod-ipt-fullconenat 在
# 全部 6 个 feed（主树 / luci fork@25.12 / packages fork / routing /
# telephony / helloworld）中均已无提供者（疑为 openwrt-25.12 分支整备期移除）。
# 不处理则在 rootfs 组装阶段 fatal：
#   pkg_hash_check_unresolved: cannot find dependency 'iptables-mod-fullconenat'
# 上游恢复提供者后本补丁自动失效（guard 检测到定义即跳过）。
# 代价：fw3 的 fullcone 选项（firewall.config 默认为 0/关闭）暂不可用，
# 其余防火墙规则不受影响。.config 中对应的两条死选择已同步清除。
# ---------------------------------------------------------------------------
if ! grep -rq "Package/iptables-mod-fullconenat" package feeds 2>/dev/null; then
  sed -i 's/ +iptables-mod-fullconenat//g' package/network/config/firewall/Makefile
fi

# ---------------------------------------------------------------------------
# 网络性能调优（写进 base-files overlay，随固件生效）
# 硬件前提：WRT1900AC V2(=WRT1900ACS, Cobra) = Marvell Armada 385 (MV88F6820)
#   双核 Cortex-A9 @1.6GHz（OpenWrt 官方 bootlog: "CPU @ 1600 [MHz]"，
#   部分中文评测/宣传页写的 1.3GHz 是 V1 Armada XP @1.33GHz 的数据，有误）
#   / 512MB RAM / 128MB NAND(UBI) / 88E6176 交换芯片 / mwlwifi 4x4 双频。
# 原则：缓冲区给上限、默认值保守，把内存留给 conntrack 和代理进程。
# ---------------------------------------------------------------------------
grep -q 'net.core.rmem_max' package/base-files/files/etc/sysctl.conf 2>/dev/null || cat >> package/base-files/files/etc/sysctl.conf << 'EOF'

# --- 吞吐：TCP 缓冲区扩容（大文件/高速下载）
# default 256KB：TCP 实际初始值由 tcp_rmem/tcp_wmem 决定，此值主要影响 UDP；
# 512MB RAM 虽然宽裕，但 UDP 默认缓冲越大越利于洪泛耗内存，256KB 足够。
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 16384 16777216

# --- 吞吐：BBR 拥塞控制 + fq_codel 队列规则
# kmod-tcp-bbr 已在 .config 选中（开机由 kmodloader 自动加载）。
# BBR 在有丢包/跨境高时延链路上的吞吐远优于 cubic。
# 队列规则用 fq_codel：lede 内核未编译 NET_SCH_FQ（generic config-6.6 中为
# not set，fq 模块需引入 kmod-sched 聚合包才能用），而 fq_codel 内建
# （NET_SCH_FQ_CODEL=y，OpenWrt 官方默认 qdisc）且自带 AQM 抗 bufferbloat；
# BBR 自 4.13 起自带内部 pacing，不强制依赖 fq。
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
# 链路 MTU 异常（PPPoE/隧道）时自动探测，避免黑洞丢包
net.ipv4.tcp_mtu_probing=1
# 长连接闲置后重置慢启动，代理长连接二次传输不再掉速
net.ipv4.tcp_slow_start_after_idle=0

# --- 吞吐：软中断收包预算（默认 300/2000us，高 PPS 下 softnet 丢包）
net.core.netdev_budget=600
net.core.netdev_budget_usecs=8000

# --- 内存：conntrack 扩容 + 超时收敛
# 代理场景连接数激增，移除 ssr-plus 后内存充裕，提至 131072（约 40MB 峰值）。
# established 默认 432000s(5 天)太长，收敛到 2h；每条表项约 300B，省下几十 MB。
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=7200

# --- 稳定：预留最低空闲内存
# 512MB 默认 min_free 仅约 4-5MB；长期运行 + 内存碎片化后，网络栈的高阶分配
# （skb 簇/驱动缓冲）失败会直接丢包。预留 16MB 安全垫，换满载时的转发稳定。
vm.min_free_kbytes=16384
EOF

# ---------------------------------------------------------------------------
# 首开机调优（uci-defaults，仅首次启动应用一次）
#   1) mwlwifi(88W8864)：关闭 802.11b 低速率，减少空口时间浪费
#   2) 国家码为空或为 config_generate 出厂默认 US 时补 CN：
#      合规使用 5.8G 149-165 信道（高功率、非 DFS），用户手动设过则不覆盖
# 注意：不建议在此硬编码信道/加密方式——信道交给 auto 或用户自选，
# DFS 信道（52-64）稳定性差会触发雷达检测重启，见 README/构建说明。
# ---------------------------------------------------------------------------
cat > package/base-files/files/etc/uci-defaults/99-wrt-tuning << 'EOF'
#!/bin/sh
# 注意：不能靠 "uci show" + sed 提取 radio 名——uci show 的值带引号
# （type='wifi-device'），按裸值匹配永不命中。改用标准 shell 库遍历。
. /lib/functions.sh
fix_radio() {
  local cfg="$1"
  uci -q set wireless.$cfg.legacy_rates='0'
  cur="$(uci -q get wireless.$cfg.country)"
  if [ -z "$cur" ] || [ "$cur" = "US" ]; then
    uci -q set wireless.$cfg.country='CN'
  fi
}
config_load wireless
config_foreach fix_radio wifi-device
uci -q commit wireless
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-wrt-tuning

# ---------------------------------------------------------------------------
# .config 追加：内核定时器频率 250Hz
# OpenWrt ARM 内核默认 100Hz，250Hz 让 NAPI/软中断/定时器粒度更细，
# 对转发延迟与 BBR 计时有可感知收益；CI 中本脚本运行于 .config 加载之后、
# make defconfig 之前，追加项会参与 defconfig 归一化。
# ---------------------------------------------------------------------------
grep -q '^CONFIG_KERNEL_HZ_250=y' .config 2>/dev/null || echo 'CONFIG_KERNEL_HZ_250=y' >> .config
