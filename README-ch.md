# V2RayPro (中文说明)

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="V2RayPro 标志" width="128" height="128" />
</p>

<p align="center">
  <strong>高性能、现代化界面的 V2Ray / Xray 与 Sing-box 客户端，集成 Cloudflare 优选 IP 扫描器</strong>
</p>

<p align="center">
  <a href="#特性功能">特性功能</a> •
  <a href="#安装指南">安装指南</a> •
  <a href="#安卓版本">安卓版本</a> •
  <a href="#界面截图">界面截图</a> •
  <a href="#支持与捐赠-donation">支持与捐赠</a> •
  <a href="#开源许可">开源许可</a>
</p>

---

### 🌐 多语言 / Languages

[English](README.md) • [فارسی](README-fa.md) • **中文** • [Русский](README-ru.md) • [Français](README-fr.md) • [Español](README-sp.md)

---

## 🚀 特性功能

- **双核多引擎驱动**：原生支持 **Xray-core** 与 **sing-box** 引擎，支持一键无缝切换。
- **广泛的协议支持**：全面兼容 VLESS、VMess、Trojan、Shadowsocks、Reality、WireGuard 及 Hysteria 协议。
- **独创 Cloudflare 优选 IP 扫描器**：
  - **雷达模式 (Radar Mode)**：全自动实时测速扫描 Cloudflare IP 段，并在不中断连接的情况下无缝切换至延迟最低的可用优选 IP。
  - **目标模式 (Target Mode)**：针对自定义 IP 段进行批量测速，支持调整并发线程数（最高 100 并发）。
  - 动态延迟改善折线图、历史记录及卡片内置的流量警示提醒。
- **全局 TUN 虚拟网卡与系统代理**：
  - 基于高速 Wintun 驱动实现真正全局透明代理流量接管。
  - 支持 HTTP / SOCKS5 本地代理，内置中国大陆及局域网域名智能分流规则。
- **高级订阅与节点管理**：
  - 智能识别 Base64 及各类通用订阅格式。
  - 支持 TCP Ping、真实 HTTP 延迟与协议握手测速。
  - 支持节点搜索、国家/地区标签筛选、节点排序与一键去重。
- **现代化桌面体验**：
  - 基于 Flutter 打造的精致界面，完美支持深色模式（Dark）与浅色模式（Light）。
  - 支持系统托盘驻留、开机自启与断线自动重连。

---

## 📸 界面截图

<p align="center">
  <img src="docs/screenshots/preview.png" alt="V2RayPro 界面预览" width="850" />
</p>

---

## 📱 安卓版本 (Android)

> **提示**：V2RayPro 的 **Android（安卓）版本** 目前正在积极开发中！  
> 移动版本将保留桌面端的核心代理路由与 Cloudflare 优选 IP 扫描能力。敬请关注我们的 [Releases 发行页面](https://github.com/iamcloner/v2raypro/releases) 获取首发公测版通知。

---

## 💻 安装指南

### Windows (x64)

1. 前往 GitHub 仓库的 [Releases 发布页面](https://github.com/iamcloner/v2raypro/releases)。
2. 下载最新版本压缩包：`v2raypro-windows-v1.7.3.zip`（或 `v2raypro-v1.7.3-windows-x64.zip`）。
3. 解压压缩包至任意文件夹（例如 `C:\Program Files\V2RayPro` 或桌面）。
4. 双击运行 `v2raypro.exe`。
   - *TUN 模式提示*：如需使用全局 TUN 虚拟网卡，建议右键以“管理员身份运行”（Run as Administrator）。

---

## 💖 支持与捐赠 (Donation)

如果您觉得 V2RayPro 对您有所帮助，并希望支持本项目的持续维护、服务器及开发，欢迎通过以下加密货币进行捐助：

| 币种 | 网络 / 符号 | 钱包地址 |
| :--- | :--- | :--- |
| **Bitcoin** | BTC | `1JpSSvLjAj3wreRogBdjTMdEykW7YsX97b` |
| **Ethereum** | ETH (ERC20) | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **Tether / Tron** | TRX / TRC20 | `TSuhDm1B7X4sz4xNjgd3Y6JGDXCgq8qv7b` |
| **BNB** | BSC (BEP20) | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **Telegram Open Network** | Gram / TON | `EQDD0fo7jSaljn5q4dO02hhC1d3xc2Hr9N5AK2JqMCguZmnB` |
| **Solana** | SOL | `E5fNLHCaZhYTWWacyCnFXLEnkLT8pkiZUqbWEEnEhHQe` |
| **Monero** | XMR | `42o9i9DacHtbzndSx9eSPBFmAFrCeW9R2RWyv1ZJeNemKTAKDyHa8jRF8Ce8j7CVqJJBURGDNipKyC4ebigbPjVRUeMRHoK` |
| **Ripple** | XRP | `raxQ5Vg3awT1U7jx1Zv1znVcCrKVCJ8HNF` |
| **Ethereum Classic** | ETC | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **Litecoin** | LTC | `LSHokx4e2pbdmJaYpKqEkJUv3R4iE9t4zZ` |
| **Cardano** | ADA | `addr1qxlavq0fu3x2dzd685shgq46v6ysyu4w3w7g4pu6r6sjl95qwrclc2a2x6x4c5fgp80m27rupavltt62ezwcmx2z8ngsam72me` |

---

## 📄 开源许可

本项目采用 MIT 许可证开源。
