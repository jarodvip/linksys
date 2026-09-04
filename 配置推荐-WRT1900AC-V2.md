# WRT1900AC V2 固件配置推荐报告

> 基于仓库 jarodvip/linksys 当前 `.config`（823 个 =y 包）、diy 脚本与 CI 工作流的全量梳理，  
> 结合设备硬件规格与「性能稳定」目标给出。生成时间：2026-09-04。

---

## 一、硬件画像（决定了所有配置取舍）

| 部件  | 规格                                                | 对配置的含义                                   |
| --- | ------------------------------------------------- | ---------------------------------------- |
| CPU | Marvell Armada 385（88F6820）双核 Cortex-A9 @ 1.33GHz | 算力有限：用户态代理（OpenClash）是唯一瓶颈；**软件流量分载必须开** |
| 内存  | 256MB DDR3                                        | 不足以同时跑全量规则集 + 大量连接；警惕 OOM                |
| 闪存  | 128MB NAND（双分区）                                   | 空间充裕，包多一点也不怕；怕的是内存不是闪存                   |
| 无线  | Marvell 88W8864（mwlwifi 驱动），AC1900（N600 + AC1300） | mwlwifi 有已知怪癖：DFS 信道、WPA3 不稳，推荐保守设置      |
| 交换机 | Marvell 88E6176，DSA 驱动（kmod-dsa-mv88e6xxx）✓ 已选    | 正确                                       |
| USB | USB 3.0 + eSATA 复合口                               | 当前**无任何 kmod-usb 包，端口不可用**（见问题 3）        |

**核心结论：这台机器的直连转发能力过剩（千兆线速无压力），短板在 CPU 用户态代理与内存。所有优化围绕"直连走分载、代理少而精、内存留余量"。**

---

## 二、现状评估

### 做得好的（保持不动）

1. **目标平台完全正确**：mvebu/cortexa9 + `DEVICE_linksys_wrt1900ac-v2`，内核 6.6（稳定版，勿切 6.18 TESTING——mwlwifi 在 6.6 上验证最充分），无线固件 `mwlwifi-firmware-88w8864` 与上游 Cobra 设备定义一致。
2. **TurboACC + 软件流量分载（FLOW_OFFLOADING）+ BBR**：正是这台 A9 该有的组合。直连 NAT 可达 900Mbps+，BBR 对代理上行有明显收益。
3. **代理栈精简**：只有 OpenClash 一个代理应用，没有装 ssr-plus/passwall 冗余组件，且备齐了 `kmod-tun`（TUN 模式）、`kmod-ipt-tproxy`（透明代理）、dnsmasq-full+ipset（分流解析）——依赖链完整。
4. **fw3/iptables 栈自洽**：LEDE 默认路径，与 OpenClash tproxy、FullCone NAT 兼容，不要动。
5. **smartdns 独立 DNS** + ddns-scripts（阿里云/DNSPod）+ autoreboot 定期重启 + nlbwmon 流量统计：都是轻量、利于长期稳定运行的组件。
6. **diy-part2.sh 的 sysctl 调优**（TCP 缓冲 16MB、conntrack 65535）对 256MB 内存是安全的量级，合理。

### 发现的问题（按影响排序）

| # | 问题                                                         | 影响                                                          | 级别     |
| - | ---------------------------------------------------------- | ----------------------------------------------------------- | ------ |
| 1 | **FullCone NAT 与流量分载互斥**（两者都编进去了）                          | 开着 FullCone 时分载对 NAT 流量失效，千兆直连跌到 ~300-400Mbps；用户常误以为"路由器不行" | ⚠️ 高   |
| 2 | **rclone 三件套**（luci-app-rclone + rclone-ng + rclone-webui） | 闪存 ~20MB、WebUI 运行吃内存；非网盘重度用户纯属负担                            | 中      |
| 3 | **USB 完全不可用**：无 kmod-usb2/usb3/storage                     | 接 U 盘/硬盘无反应；block-mount 孤立无伴                                | 中（看需求） |
| 4 | **Argon 主题丢失**：项目记忆中本应含 Argon，现只剩 bootstrap                | 与项目初衷不符；bootstrap 功能无碍但可读性差                                 | 低      |
| 5 | **vlmcsd**（KMS 激活服务）                                       | 常驻监听端口，家用基本用不到                                              | 低      |
| 6 | **无 zram/无内存兜底**                                           | OpenClash 全量规则 + smartdns + 异常连接数下有 OOM 风险，OOM 即断网重启        | 中      |
| 7 | 无 irqbalance / 无轻量诊断工具（htop 等）                             | 双核软中断集中单核时吞吐波动；排障不便                                         | 低      |

---

## 三、推荐变更

### A. 必改（性能稳定直接相关）

**A1. 明确 FullCone 与分载的使用策略**（不改包，改用法）

- 日常：TurboACC 里**只开"软件流量分载"**，FullCone 关闭 → 直连跑满千兆
- 需要游戏 NAT 类型改善时：临时开 FullCone、关分载（游戏对带宽不敏感，对 NAT 类型敏感，两者正好互补）
- 说明：`kmod-ipt-fullconenat` 两个包保留在固件里没有运行时代价，按需切换即可

**A2. 卸掉 rclone 三件套**（若不做网盘挂载）

```diff
# .config 删除
-CONFIG_PACKAGE_luci-app-rclone_INCLUDE_rclone-ng=y
-CONFIG_PACKAGE_luci-app-rclone_INCLUDE_rclone-webui=y
-CONFIG_PACKAGE_luci-app-rclone=y
```

**A3. 加 zram 兜底**（256MB 内存的保险丝，压缩换内存，代价很小）

```diff
+CONFIG_PACKAGE_zram-swap=y
```

### B. 建议（补齐短板）

**B1. 恢复 Argon 主题**（补回项目初衷，体积 <1MB）

```diff
+CONFIG_PACKAGE_luci-theme-argon=y
```

**B2. 轻量运维工具**（共 <1MB）

```diff
+CONFIG_PACKAGE_htop=y
+CONFIG_PACKAGE_irqbalance=y      # 双核软中断均衡，mvneta+mwlwifi 场景有收益
```

**B3. 移除 vlmcsd**

```diff
-CONFIG_PACKAGE_vlmcsd=y
+# CONFIG_PACKAGE_vlmcsd is not set
```

### C. 可选（按需求）

**C1. 若要用 USB 口**（rclone 卸了但偶尔想接盘/USB 网卡共享）：

```diff
+CONFIG_PACKAGE_kmod-usb2=y
+CONFIG_PACKAGE_kmod-usb3=y
+CONFIG_PACKAGE_kmod-usb-storage=y
+CONFIG_PACKAGE_kmod-fs-ext4=y    # 或 kmod-fs-exfat（NTFS 的 ntfs-3g 性能差，不建议）
```

**C2. 若宽带 ≤300Mbps 且在意游戏/会议延迟**，可加 SQM（cake 在 A9 上约能整形 200-250Mbps，够用但会占 CPU）：

```diff
+CONFIG_PACKAGE_luci-app-sqm=y
```

（500Mbps 以上宽带不建议，CPU 整形跟不上，得不偿失。）

**C3. Argon 配置面板**（可选）：`+CONFIG_PACKAGE_luci-app-argon-config=y`

---

## 四、刷机后的运行时设置（和编译同样重要）

### 无线（mwlwifi 稳定性关键）

| 项    | 推荐值                                        | 原因                            |
| ---- | ------------------------------------------ | ----------------------------- |
| 2.4G | 信道 1/6/11 固定、**20MHz**、WPA2-PSK (CCMP/AES) | 40MHz 在密集环境反而慢且断流             |
| 5G   | 信道 36-48 固定、80MHz、**避开 52-144（DFS）**       | mwlwifi 在 DFS 信道有雷达误检重启的已知怪癖  |
| 加密   | **WPA2，不用 WPA3/WPA2-WPA3 混合**              | mwlwifi 的 SAE 实现不稳，掉线多发生在混合模式 |
| 国家码  | CN                                         | 保证功率表与信道合法                    |
| 其他   | 关闭 802.11r/k/v（wpad-basic 不含也无妨）、不做 WDS    | 每多一个特性多一个不稳定因子                |

### OpenClash（决定代理体验）

- 核心：**Meta（mihomo）**，装好后从 GitHub 下载核心——首次配置时若无代理可能下载失败，提前在电脑上下载好放入 `/etc/openclash/core/`
- 模式：**fake-ip**（比 redir-host 延迟低、CPU 占用小）
- 规则：**用精简规则集**（几千条为佳），不要上"全量订阅转换"；每个规则集都是内存和匹配耗时
- 开启 `tcp-concurrent`；UDP 仅在确有需求（游戏/语音）时开
- 上游 DNS 交给 OpenClash 内建 DNS（劫持 53），smartdns 监听独立端口做国内解析，**避免两者抢 53 端口**
- 期望管理预期：**代理吞吐 80–200Mbps**（协议决定：ss/trojan 快，vmess+ws+tls 慢），这不是配置问题，是 1.33GHz 双核 A9 的物理极限；千兆代理请上 x86/软路由

### TurboACC

- 仅开「软件流量分载」+「BBR」；FullCone 按需临时切换（见 A1）

### 系统习惯

- autoreboot 建议每周日凌晨 4 点（已装，刷机后确认周期）
- 系统日志输出到 RAM（/tmp）而非闪存：默认即如此，不要手动改持久化
- nlbwmon 月度报表足够；不必再装 bandwidthd/collectd 全家桶

---

## 五、预期性能基线（改完后）

| 场景                  | 预期                                                           |
| ------------------- | ------------------------------------------------------------ |
| 有线直连 NAT（分载开）       | 900Mbps+，CPU <30%                                            |
| OpenClash 代理        | 80–200Mbps（视协议），CPU 60–90%                                   |
| 2.4G WiFi           | 100–150Mbps 实测                                               |
| 5G WiFi（2x2 AC 客户端） | 400–600Mbps 实测                                               |
| 空闲内存                | 刷机后 ~180MB；OpenClash 精简规则运行时 ~120–150MB（加 zram 后 OOM 风险基本消除） |

---

## 六、落地清单

- [ ] 按 A2/A3/B1/B2/B3 修改 `.config`（净变化：-4 删 +4 增，固件体积基本不变，内存压力下降）
- [ ] 提交推送（GPG 签名走 /tmp 副本流程）
- [ ] 触发构建，产出固件
- [ ] 刷机后按第四节做运行时设置（无线信道/加密、OpenClash 核心、TurboACC、smartdns 端口分工）
- [ ] 观察一周：`free`、`top`、nlbwmon，确认无 OOM、无规律性掉线

> 注：上述 `.config` 变更已于 2026-09-05 应用并提交。验证构建 run 33887064596 仅验证 IEI 补丁修复、不含本变更；含本变更的固件需另行触发构建。
