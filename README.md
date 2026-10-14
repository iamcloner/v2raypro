# V2RayPro

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="V2RayPro Logo" width="128" height="128" />
</p>

<p align="center">
  <strong>High-performance, modern GUI client for V2Ray / Xray & Sing-box with integrated Cloudflare Clean IP Scanner</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#android-version">Android Version</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#donation">Donation</a> •
  <a href="#license">License</a>
</p>

---

### 🌐 Languages / زبان‌ها / 语言 / Языки / Langues / Idiomas

| Language | File |
| :--- | :--- |
| **English** | [README.md](README.md) |
| **فارسی (Persian)** | [README-fa.md](README-fa.md) |
| **中文 (Simplified Chinese)** | [README-ch.md](README-ch.md) |
| **Русский (Russian)** | [README-ru.md](README-ru.md) |
| **Français (French)** | [README-fr.md](README-fr.md) |
| **Español (Spanish)** | [README-sp.md](README-sp.md) |

---

## 🚀 Features

- **Multi-Core Engine**: Native support for **Xray-core** and **sing-box** engines with effortless switching.
- **Protocol Versatility**: Full support for VLESS, VMess, Trojan, Shadowsocks, Reality, WireGuard, and Hysteria protocols.
- **Cloudflare Clean IP Scanner**:
  - **Radar Mode**: Automatically explores Cloudflare IP ranges in real-time and latches onto the lowest-latency clean IP without disconnecting.
  - **Target Mode**: Tests targeted IP ranges with customizable concurrent connections (up to 100 workers).
  - Dynamic latency improvement history and inline bandwidth-saving traffic alerts.
- **Global TUN & System Proxy Modes**:
  - Transparent system-wide routing via high-speed wintun driver.
  - HTTP / SOCKS5 system proxy support with smart bypass rules for local and domestic domains.
- **Advanced Subscription & Node Management**:
  - Automatic base64 and standard subscription parser.
  - Delay testing: TCP ping, real HTTP delay, and protocol-level speed probe.
  - Search, filter by country/tag, duplicate removal, and sort.
- **Modern User Experience**:
  - Clean Flutter desktop interface with responsive dark and light themes.
  - Multi-language localization (English, Persian, etc.).
  - System tray minimization, auto-reconnect, and auto-start on boot.

---

## 📸 Screenshots

<p align="center">
  <img src="docs/screenshots/Dashboard.png" alt="Dashboard" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/CDN-scanner.png" alt="Cloudflare Scanner" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/Configs.png" alt="Configs Management" width="400" />
  <img src="docs/screenshots/Free-configs.png" alt="Free Configs" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Subs.png" alt="Subscriptions" width="400" />
  <img src="docs/screenshots/Routing.png" alt="Routing Rules" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Settings-1.png" alt="Settings General" width="400" />
  <img src="docs/screenshots/Settings-2.png" alt="Settings Core & Protocols" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Logs.png" alt="Core Logs" width="800" />
</p>

---

## 📱 Android Version

> **Note**: The **Android version** of V2RayPro is currently under active development.  
> It will bring the full power of V2RayPro, including core routing and Cloudflare clean IP scanning, to mobile devices. Stay tuned for the upcoming beta release in the [Releases](https://github.com/iamcloner/v2raypro/releases) page!

---

## 💻 Installation

### Windows (x64)

1. Navigate to the latest release on the [GitHub Releases](https://github.com/iamcloner/v2raypro/releases) page.
2. Download `v2raypro-windows-v1.7.3.zip` (or `v2raypro-v1.7.3-windows-x64.zip`).
3. Extract the downloaded zip file into any folder (e.g., `C:\Program Files\V2RayPro` or Desktop).
4. Run `v2raypro.exe`.
   - *Optional for TUN mode*: Run as Administrator to allow Windows virtual network adapter (Wintun) creation.

---

## 💖 Donation & Support

If you find V2RayPro helpful and would like to support ongoing development and server maintenance, you can donate via cryptocurrency:

| Coin | Network / Symbol | Address |
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

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
