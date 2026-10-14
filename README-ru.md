# V2RayPro (Русская документация)

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="Логотип V2RayPro" width="128" height="128" />
</p>

<p align="center">
  <strong>Высокопроизводительный современный клиент для V2Ray / Xray и Sing-box со встроенным сканером чистых IP Cloudflare</strong>
</p>

<p align="center">
  <a href="#возможности">Возможности</a> •
  <a href="#установка">Установка</a> •
  <a href="#версия-для-android">Версия для Android</a> •
  <a href="#скриншоты">Скриншоты</a> •
  <a href="#поддержка-и-пожертвования-donation">Пожертвования</a> •
  <a href="#лицензия">Лицензия</a>
</p>

---

### 🌐 Языки / Languages

[English](README.md) • [فارسی](README-fa.md) • [中文](README-ch.md) • **Русский** • [Français](README-fr.md) • [Español](README-sp.md)

---

## 🚀 Возможности

- **Многоядерный движок**: Нативная поддержка ядер **Xray-core** и **sing-box** с мгновенным переключением в один клик.
- **Широкая поддержка протоколов**: Совместимость с VLESS, VMess, Trojan, Shadowsocks, Reality, WireGuard и Hysteria.
- **Умный сканер чистых IP Cloudflare**:
  - **Режим Радар (Radar Mode)**: Автоматический поиск и тестирование диапазонов Cloudflare в реальном времени с мгновенным переключением на лучший IP без разрыва соединения.
  - **Режим Таргет (Target Mode)**: Пакетное тестирование выбранных подсетей с настройкой параллельных потоков (до 100 воркеров).
  - История снижения задержки и компактные уведомления о расходе трафика внутри интерфейса.
- **Глобальный TUN и системный прокси**:
  - Полная прозрачная маршрутизация всего трафика через быстрый драйвер Wintun.
  - Поддержка системного HTTP / SOCKS5 прокси с умными правилами обхода локальных сетей.
- **Управление подписками и узлами**:
  - Распознавание Base64 и популярных форматов подписок.
  - Проверка задержки: TCP пинг, реальный HTTP ping и проверка протокола.
  - Поиск, фильтрация по странам/тегам, сортировка и удаление дубликатов.
- **Современный интерфейс**:
  - Быстрый и плавный интерфейс на Flutter с поддержкой темной и светлой темы.
  - Сворачивание в системный трей, автоподключение и автозапуск при включении Windows.

---

## 📸 Скриншоты

<p align="center">
  <img src="docs/screenshots/Dashboard.png" alt="Панель управления и статус подключения" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/CDN-scanner.png" alt="Сканер чистых IP Cloudflare" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/Configs.png" alt="Управление узлами и конфигурациями" width="400" />
  <img src="docs/screenshots/Free-configs.png" alt="Бесплатные конфигурации" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Subs.png" alt="Управление подписками" width="400" />
  <img src="docs/screenshots/Routing.png" alt="Правила маршрутизации" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Settings-1.png" alt="Общие настройки" width="400" />
  <img src="docs/screenshots/Settings-2.png" alt="Настройки ядер и протоколов" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Logs.png" alt="Журнал работы ядра" width="800" />
</p>

---

## 📱 Версия для Android

> **Примечание**: **Версия V2RayPro для Android** в настоящее время находится в активной разработке!  
> Мобильная версия объединит всю мощь маршрутизации ядер и сканера IP Cloudflare на смартфонах. Следите за обновлениями на странице [Releases](https://github.com/iamcloner/v2raypro/releases), чтобы первыми опробовать бета-версию!

---

## 💻 Установка

### Windows (x64)

1. Перейдите в раздел [GitHub Releases](https://github.com/iamcloner/v2raypro/releases).
2. Скачайте архив последней версии: `v2raypro-windows-v1.7.3.zip` (или `v2raypro-v1.7.3-windows-x64.zip`).
3. Распакуйте скачанный zip-архив в любую удобную папку (например, `C:\Program Files\V2RayPro` или на Рабочий стол).
4. Запустите `v2raypro.exe`.
   - *Для режима TUN*: Запустите от имени администратора (Run as Administrator) для корректного создания сетевого адаптера Wintun.

---

## 💖 Поддержка и пожертвования (Donation)

Если вам нравится V2RayPro и вы хотите поддержать дальнейшую разработку, поддержку серверов и добавление новых функций, вы можете отправить пожертвование в криптовалюте:

| Монета | Сеть / Символ | Адрес кошелька |
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

## 📄 Лицензия

Проект распространяется под открытой лицензией MIT.
