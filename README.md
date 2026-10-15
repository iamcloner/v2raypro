# V2RayPro

<p align="center">
  <strong>Fast, Modern & Advanced Multi-Platform V2Ray / Xray & Sing-box Client</strong>
</p>

This workspace is organized into two isolated platform projects:

- **[Windows (Desktop)](windows/)**: High-performance Windows client with native Rust core integration, Wintun global TUN routing, Cloudflare clean IP radar/target scanner, and system proxy management.
- **[Android (Mobile)](android/)**: Native Android client powered by Android VpnService, authentic Real Delay ping (~600ms), Telegram-style navigation, and per-app routing. (Tracked at [v2raypro-android](https://github.com/iamcloner/v2raypro-android)).

---

## 📁 Project Structure

`
v2raypro/
├── android/    # Standalone Android Client (Flutter + Android VpnService)
└── windows/    # Standalone Windows Client (Flutter + Rust + Wintun)
`

## 📄 License
GPL-3.0 License.