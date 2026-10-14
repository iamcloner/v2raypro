# V2RayPro

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="V2RayPro Logo" width="100" height="100" />
</p>

<p align="center">
  <strong>高性能 V2Ray / Xray 与 Sing-box 客户端，集成 Cloudflare 优选 IP 扫描器</strong>
</p>

<p align="center">
  <a href="README.md">English</a> • <a href="README-fa.md">فارسی</a> • 中文 • <a href="README-ru.md">Русский</a> • <a href="README-fr.md">Français</a> • <a href="README-sp.md">Español</a>
</p>

---

## 🚀 特性功能

- **多内核支持**：原生支持 Xray-core 与 Sing-box 双内核，支持一键无缝切换。
- **协议兼容**：支持 VLESS、VMess、Trojan、Shadowsocks、Reality、WireGuard 及 Hysteria。
- **Cloudflare 优选 IP 扫描器**：
  - *雷达模式*：全自动探测低延迟 IP 并实现无感热切换。
  - *目标模式*：批量测速自定义 IP 段，最高支持 100 并发测试。
- **路由模式**：全局 TUN 虚拟网卡（Wintun）与系统代理（HTTP/SOCKS5），支持域名规则分流。
- **节点与订阅管理**：支持 Base64 及通用订阅导入，真实 HTTP/TCP 延迟测速，节点一键去重。
- **现代交互**：基于 Flutter 构建，支持深色/浅色主题，支持托盘驻留与开机自启。

---

## 📸 界面截图

<p align="center">
  <img src="docs/screenshots/Dashboard.png" alt="仪表盘" width="480" />
  <img src="docs/screenshots/CDN-scanner.png" alt="优选 IP 扫描器" width="480" />
</p>

<p align="center">
  <img src="docs/screenshots/Configs.png" alt="节点列表" width="235" />
  <img src="docs/screenshots/Free-configs.png" alt="免费节点" width="235" />
  <img src="docs/screenshots/Subs.png" alt="订阅管理" width="235" />
  <img src="docs/screenshots/Routing.png" alt="路由分流" width="235" />
</p>

<p align="center">
  <img src="docs/screenshots/Settings-1.png" alt="通用设置" width="315" />
  <img src="docs/screenshots/Settings-2.png" alt="内核设置" width="315" />
  <img src="docs/screenshots/Logs.png" alt="内核日志" width="315" />
</p>

---

## 💻 安装指南

### Windows (x64)
1. 前往 [GitHub Releases](https://github.com/iamcloner/v2raypro/releases) 下载最新压缩包 `v2raypro-windows-v1.7.3.zip`。
2. 解压压缩包至任意目录。
3. 运行 `v2raypro.exe`（使用 TUN 模式请以管理员身份运行）。

### 安卓版本 (Android)
> 📱 **提示**：**Android 版本** 目前正在全力开发中，发布后将第一时间在 [GitHub Releases](https://github.com/iamcloner/v2raypro/releases) 页面提供下载。

---

## 💖 支持与捐赠 (Donation)

如果您觉得 V2RayPro 对您有所帮助并愿意支持项目的持续开发：

| 币种 | 网络 | 钱包地址 |
| :--- | :--- | :--- |
| **BTC** | Bitcoin | `1JpSSvLjAj3wreRogBdjTMdEykW7YsX97b` |
| **ETH** | ERC20 | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **TRX** | TRC20 | `TSuhDm1B7X4sz4xNjgd3Y6JGDXCgq8qv7b` |
| **BNB** | BEP20 | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **TON / Gram** | TON | `EQDD0fo7jSaljn5q4dO02hhC1d3xc2Hr9N5AK2JqMCguZmnB` |
| **SOL** | Solana | `E5fNLHCaZhYTWWacyCnFXLEnkLT8pkiZUqbWEEnEhHQe` |
| **XMR** | Monero | `42o9i9DacHtbzndSx9eSPBFmAFrCeW9R2RWyv1ZJeNemKTAKDyHa8jRF8Ce8j7CVqJJBURGDNipKyC4ebigbPjVRUeMRHoK` |
| **XRP** | Ripple | `raxQ5Vg3awT1U7jx1Zv1znVcCrKVCJ8HNF` |
| **ETC** | ETC | `0xE90973336d5c09B1183A8ddc4f27b1647Cbdc52A` |
| **LTC** | Litecoin | `LSHokx4e2pbdmJaYpKqEkJUv3R4iE9t4zZ` |
| **ADA** | Cardano | `addr1qxlavq0fu3x2dzd685shgq46v6ysyu4w3w7g4pu6r6sjl95qwrclc2a2x6x4c5fgp80m27rupavltt62ezwcmx2z8ngsam72me` |

---

## 📄 开源许可

本项目基于 MIT 协议开源。

