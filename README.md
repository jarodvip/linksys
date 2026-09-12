# linksys · OpenWrt 固件构建仓库

基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 模板，使用
[coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)（Lean）源码，通过 **GitHub Actions
自动构建** Linksys 路由器的 OpenWrt 固件，并以 **GitHub Releases** 发布二进制。

## 目标设备

| 项 | 值 |
|---|---|
| 设备 | Linksys **WRT1900AC V2**（WRT1900ACS, Cobra） |
| SoC | Marvell Armada 385，`mvebu / cortexa9`（双核 Cortex-A9 @1.6GHz） |
| 包架构 | `arm_cortex-a9_vfpv3-d16` |
| 内存 / 存储 | 512MB RAM / 128MB NAND(UBI) |
| 内核 | lede master，Linux 6.6（构建时随上游锁定） |
| 默认管理 IP | `192.168.2.1` |

## 固件特性

- **OpenClash**（`luci-app-openclash`）代理；核心（Meta/Clash 内核）**不**内置于固件，
  首次使用需在页面或手工上传内核到 `/etc/openclash/core/`。
- **Turbo ACC**（软件分载 / 硬件分载）+ **BBR** 拥塞控制。
- LuCI with **中文界面**（`luci-i18n-base-zh-cn`）+ argon 主题。
- 网络调优通过 `diy-part2.sh` 写入：TCP 缓冲扩容、`default_qdisc=fq_codel`、
  `tcp_congestion_control=bbr`、`nf_conntrack_max=131072`、`vm.min_free_kbytes=16M` 等。
- 精简 rootfs，**factory.img 约 23MiB**（xZ 压缩、256K block），位于 Linksys OEM 上传硬限制之下。

## 刷入 / 升级

1. 在仓库 `Actions` 页手动 `Run workflow`，或由 `update-checker` 在 lede 源码更新时自动触发；
   产物会发布到 **Releases**。
2. 下载 `*squashfs-factory.img`：
   - **从原厂固件升级**：进入原厂 Web 界面上传 `factory.img`（Linksys WRT AC 系 OEM 上传有
     ~32MiB 硬限制，本固件约 23MiB，可直刷）。
   - **从已有 OpenWrt 升级**：进入 OpenWrt 或 `sysupgrade` 使用 `*squashfs-sysupgrade.bin`。
3. 刷完后访问默认 `192.168.2.1`，首次配置请打开 OpenClash 并**下载/上传内核**。

## 仓库结构

| 文件 | 作用 |
|---|---|
| `.config` | 包与内核选择（含精简与注释说明） |
| `diy-part1.sh` | feeds 调整：仅当缺失时才添加 `helloworld` feed，避免重复冲突 |
| `diy-part2.sh` | 构建后定制：删除 IEI 内核补丁、修复防火墙依赖水坑、写入 network 调优、uci-defaults（国家码 CN / 关 b 低速率）、HZ=250 |
| `.github/workflows/openwrt-builder.yml` | 主构建与发布流程（含 32MiB 体积告警） |
| `.github/workflows/update-checker.yml` | lede 源码更新自动检查（schedule） |

## 修改后如何触发一次构建

构建工作流仅监听 `workflow_dispatch` 与 `repository_dispatch`，**push 不直接触发**。
提交改动后需：

```bash
gh workflow run openwrt-builder.yml --repo jarodvip/linksys --ref main
```

若开启 `update-checker` 的 schedule，lede 源码有更新时会通过 `repository_dispatch`
自动触发一次构建。

## 已知限制

- Linksys WRT AC 系原厂 GUI 上传硬限制 ~32MiB；自编译固件必须 < 32MiB（理想 ≤ 30MiB）。
- `fw3` 防火墙 `fullcone` 选项当前暂不可用（`iptables-mod-fullconenat` 阶段性缺源，
  见 `diy-part2.sh` 注释；上游恢复后会自动失效）。
- 建议使用自编译固件前备份原厂引导/配置。

## 致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)
- [OpenWrt](https://openwrt.org) / [Mikubill/transfer](https://github.com/Mikubill/transfer) 等上游工具

## 许可

[MIT](https://github.com/P3TERX/Actions-OpenWrt/blob/main/LICENSE) © P3TERX
(本项目为个人固件定制仓库，兼容上游 MIT)。