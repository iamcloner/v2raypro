# V2Ray Pro

A professional, high-performance, and production-ready V2Ray / Xray client for **Windows** and **Android** featuring an integrated **Cloudflare Candidate IP Scanner & Benchmark Engine**.

---

## ?? Key Features

1. **Protocol Support**:
   - VLESS (Reality, TLS, WebSocket, gRPC)
   - VMess (TLS, WebSocket, TCP)
   - Trojan (TLS, WebSocket, gRPC)
   - Shadowsocks (Standard ciphers)
   - Subscription URLs (Base64 decoded auto-updates)

2. **Advanced Cloudflare Scanner**:
   - Automated detection of Cloudflare CDN-backed nodes.
   - Non-blocking candidate sampling from official Cloudflare subnets.
   - Multi-stage pipeline: **TCP Connect ? TLS Handshake (with real SNI) ? Protocol Probe**.
   - Real-time streaming results with latency classification (Excellent, Good, Average, Poor).
   - One-click **Apply Clean IP** with configuration backup and rollback safety.

3. **Modern Material 3 Interface**:
   - Dark Modern theme with systematic color tokens and smooth animations.
   - Responsive layouts: Desktop NavigationRail on Windows / Bottom NavigationBar on Android.
   - Full Internationalization (i18n): English and **Persian (?????)** with native RTL support.

4. **Robust Architecture**:
   - **Rust Core**: Independent high-throughput network scanner, Xray process manager, and secure local storage.
   - **FFI & Event Streams**: Non-blocking asynchronous event communication between Flutter and Rust.
   - **Android VPNService**: Native TUN interface with persistent foreground service and notification.
   - **Mock Scan Mode**: Built-in simulator for instantaneous UI/UX testing in offline environments.

---

## ??? Project Architecture

```
v2raypro/
+-- rust/                      # Native Core Engine (Rust)
¦   +-- src/
¦   ¦   +-- api/               # FFI C-API & Event Callbacks
¦   ¦   +-- config/            # Parser for VLESS, VMess, Trojan, SS, JSON
¦   ¦   +-- networking/        # TCP & TLS Handshake Probes
¦   ¦   +-- scanner/           # Cloudflare candidate selection & benchmarks
¦   ¦   +-- xray/              # Xray JSON builder & process supervisor
¦   ¦   +-- storage/           # Encrypted local JSON store
¦   ¦   +-- utils/             # Cloudflare CIDR matcher & error models
¦   +-- tests/                 # Core unit & integration tests
¦
+-- flutter/                   # Cross-Platform Frontend (Flutter / Dart)
¦   +-- lib/
¦   ¦   +-- core/              # FFI bridge, M3 Theme, i18n (en/fa)
¦   ¦   +-- features/          # Dashboard, Configs, Scanner, Settings
¦   ¦   +-- models/            # Entity models mirroring Rust core
¦   ¦   +-- providers/         # Riverpod state notifiers & streams
¦   +-- test/                  # Widget & smoke tests
¦
+-- android/                   # Android VpnService & platform channel
+-- docs/                      # Technical specifications & guides
```

---

## ?? How to Run & Build

### Prerequisites
- [Flutter SDK](https://flutter.dev) (>= 3.19.0)
- [Rust Toolchain](https://rustup.rs) (>= 1.75.0)

### Run Desktop (Windows)
```bash
cd flutter
flutter pub get
flutter run -d windows
```

### Run Android
```bash
cd flutter
flutter pub get
flutter run -d android
```

### Build Releases
```bash
# Windows
flutter build windows --release

# Android APK & App Bundle
flutter build apk --release
flutter build appbundle --release
```

---

## ?? Security
- UUIDs, passwords, and private keys are never exposed in log outputs.
- All processes and URL parsers employ strict bounds and format checks.
- Scanner respects concurrency limits and prevents aggressive port exhaustion.
