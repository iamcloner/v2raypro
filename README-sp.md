# V2RayPro (Documentación en español)

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="Logo de V2RayPro" width="128" height="128" />
</p>

<p align="center">
  <strong>Cliente gráfico moderno y de alto rendimiento para V2Ray / Xray y Sing-box con escáner de IP limpias de Cloudflare integrado</strong>
</p>

<p align="center">
  <a href="#características">Características</a> •
  <a href="#instalación">Instalación</a> •
  <a href="#versión-para-android">Versión para Android</a> •
  <a href="#capturas-de-pantalla">Capturas de pantalla</a> •
  <a href="#donaciones-y-apoyo-donation">Donaciones</a> •
  <a href="#licencia">Licencia</a>
</p>

---

### 🌐 Idiomas / Languages

[English](README.md) • [فارسی](README-fa.md) • [中文](README-ch.md) • [Русский](README-ru.md) • [Français](README-fr.md) • **Español**

---

## 🚀 Características

- **Motor multinúcleo**: Soporte nativo para núcleos **Xray-core** y **sing-box** con cambio instantáneo con un solo clic.
- **Amplia variedad de protocolos**: Compatibilidad total con VLESS, VMess, Trojan, Shadowsocks, Reality, WireGuard e Hysteria.
- **Escáner inteligente de IP limpias de Cloudflare**:
  - **Modo Radar**: Exploración automática y en vivo de rangos de IP de Cloudflare, conectándose a la IP con menor latencia en tiempo real sin desconectar tu conexión.
  - **Modo Objetivo (Target)**: Pruebas por lotes de rangos de IP específicos con control de concurrencia ajustable (hasta 100 hilos).
  - Historial de mejora de ping y avisos compactos de consumo de tráfico dentro de la tarjeta de conexión.
- **Modos TUN Global y Proxy del Sistema**:
  - Enrutamiento transparente de todo el tráfico del sistema mediante el controlador de alta velocidad Wintun.
  - Proxy del sistema HTTP / SOCKS5 con bypass inteligente para dominios y redes locales.
- **Gestión avanzada de suscripciones y nodos**:
  - Detección automática de enlaces de suscripción Base64 y formatos estándar.
  - Pruebas de latencia: Ping TCP, latencia HTTP real y verificación de protocolo.
  - Búsqueda rápida, filtrado por países/etiquetas, ordenación y eliminación de duplicados.
- **Experiencia de usuario moderna**:
  - Interfaz de escritorio rápida y fluida construida en Flutter, con modos claro y oscuro.
  - Minimización a la bandeja del sistema (System Tray), reconexión automática e inicio con Windows.

---

## 📸 Capturas de pantalla

<p align="center">
  <img src="docs/screenshots/preview.png" alt="Vista previa de la interfaz de V2RayPro" width="850" />
</p>

---

## 📱 Versión para Android

> **Nota**: ¡La **versión para Android** de V2RayPro se encuentra actualmente en desarrollo activo!  
> Llevará toda la potencia del enrutamiento de núcleos y el escáner de IP de Cloudflare a dispositivos móviles. ¡Sigue atento a los próximos lanzamientos beta en nuestra página de [Releases](https://github.com/iamcloner/v2raypro/releases)!

---

## 💻 Instalación

### Windows (x64)

1. Ve a la página de lanzamientos en [GitHub Releases](https://github.com/iamcloner/v2raypro/releases).
2. Descarga el archivo comprimido de la última versión: `v2raypro-windows-v1.7.3.zip` (o `v2raypro-v1.7.3-windows-x64.zip`).
3. Descomprime el archivo zip en cualquier carpeta de tu preferencia (por ejemplo, `C:\Program Files\V2RayPro` o en el Escritorio).
4. Ejecuta `v2raypro.exe`.
   - *Para modo TUN*: Ejecuta como Administrador (Run as Administrator) para permitir la creación del adaptador de red virtual Wintun.

---

## 💖 Donaciones y apoyo (Donation)

Si encuentras útil V2RayPro y deseas apoyar el desarrollo continuo, el mantenimiento de servidores y las actualizaciones, puedes realizar una donación en criptomonedas:

| Criptomoneda | Red / Símbolo | Dirección de billetera |
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

## 📄 Licencia

Este proyecto está bajo la licencia MIT.
