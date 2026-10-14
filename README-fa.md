# نرم‌افزار V2RayPro (نسخه ویندوز)

<p align="center">
  <img src="flutter/assets/app_icon.png" alt="لوگوی V2RayPro" width="128" height="128" />
</p>

<p align="center">
  <strong>کلاینت مدرن، پرسرعت و قدرتمند V2Ray / Xray و Sing-box به همراه اسکنر هوشمند آی‌پی سالم کلودفلر</strong>
</p>

<p align="center">
  <a href="#ویژگی‌ها">ویژگی‌ها</a> •
  <a href="#روش-نصب-و-اجرا">روش نصب</a> •
  <a href="#نسخه-اندروید">نسخه اندروید</a> •
  <a href="#تصاویر-برنامه">تصاویر</a> •
  <a href="#حمایت-مالی-از-پروژه-donation">حمایت مالی</a> •
  <a href="#مجوز">مجوز</a>
</p>

---

### 🌐 زبان‌ها / Languages

[English](README.md) • **فارسی** • [中文](README-ch.md) • [Русский](README-ru.md) • [Français](README-fr.md) • [Español](README-sp.md)

---

## ✨ قابلیت‌ها و ویژگی‌ها

- **هسته‌های چندگانه قدرتمند**: پشتیبانی بومی از هر دو هسته قدرتمند **Xray-core** و **Sing-box** با امکان تغییر سریع هسته.
- **پشتیبانی کامل از پروتکل‌ها**: سازگاری با پروتکل‌های VLESS، VMess، Trojan، Shadowsocks، Reality، WireGuard و Hysteria.
- **اسکنر اختصاصی آی‌پی تمیز کلودفلر (Cloudflare Scanner)**:
  - **حالت رادار (Radar Mode)**: جستجوی خودکار و زنده میان رنج‌های آی‌پی کلودفلر و سوییچ لحظه‌ای روی بهترین پینگ بدون قطعی اینترنت.
  - **حالت تارگت (Target Mode)**: تست دسته‌ای رنج‌های آی‌پی دلخواه با تنظیم هوشمند تعداد تست همزمان (تا سقف ۱۰۰ ورکر).
  - آکاردئون تاریخچه بهبود پینگ و هشدار بهینه‌شده مصرف حجم در داخل کارت اتصال.
- **حالت‌های اتصال پیشرفته**:
  - **حالت تمام‌صفحه TUN (شبکه مجازی)**: هدایت کل ترافیک سیستم‌عامل با درایور پرسرعت Wintun.
  - **حالت پروکسی سیستم (System Proxy)**: پروکسی HTTP/SOCKS5 به همراه روتینگ هوشمند و بای‌پس سایت‌های ایرانی و داخلی.
- **مدیریت پیشرفته سابسکریپشن و کانفیگ‌ها**:
  - خواندن خودکار لینک‌های ساب base64 و فرمت‌های استاندارد.
  - تست تاخیر با پینگ TCP، تاخیر واقعی HTTP و پروب پروتکل.
  - جستجو، فیلتر کشورها و تگ‌ها، مرتب‌سازی و حذف کانفیگ‌های تکراری.
- **طراحی زیبا و مدرن**:
  - رابط کاربری دسکتاپ بر پایه Flutter با پشتیبانی از تم تاریک (Dark Mode) و روشن (Light Mode).
  - پشتیبانی از زبان فارسی و انگلیسی.
  - قرارگیری در سینی سیستم (System Tray)، اتصال خودکار هنگام بالا آمدن ویندوز و پایداری بالا.

---

## 📸 تصاویر برنامه

<p align="center">
  <img src="docs/screenshots/Dashboard.png" alt="داشبورد و وضعیت اتصال" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/CDN-scanner.png" alt="اسکنر هوشمند آی‌پی کلودفلر" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/Configs.png" alt="مدیریت کانفیگ‌ها" width="400" />
  <img src="docs/screenshots/Free-configs.png" alt="کانفیگ‌های رایگان روزانه" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Subs.png" alt="مدیریت لینک‌های سابسکریپشن" width="400" />
  <img src="docs/screenshots/Routing.png" alt="تنظیمات روتینگ و مسیریابی" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Settings-1.png" alt="تنظیمات عمومی" width="400" />
  <img src="docs/screenshots/Settings-2.png" alt="تنظیمات هسته‌ها و پروتکل‌ها" width="400" />
</p>

<p align="center">
  <img src="docs/screenshots/Logs.png" alt="لاگ‌های زنده هسته" width="800" />
</p>

---

## 📱 نسخه اندروید

> **نکته**: **نسخه اندروید** V2RayPro در حال حاضر در دست توسعه فعال قرار دارد.  
> این نسخه تمام امکانات هسته روتینگ و اسکنر آی‌پی کلودفلر را به دستگاه‌های موبایل خواهد آورد. به زودی نسخه آزمایشی در صفحه [انتشارها (Releases)](https://github.com/iamcloner/v2raypro/releases) منتشر خواهد شد.

---

## 💻 روش نصب و اجرا

### ویندوز (نسخه ۶۴ بیتی)

۱. به صفحه [انتشارهای گیت‌هاب (GitHub Releases)](https://github.com/iamcloner/v2raypro/releases) مراجعه کنید.  
۲. آخرین نسخه فایل فشرده (`v2raypro-windows-v1.7.3.zip` یا `v2raypro-v1.7.3-windows-x64.zip`) را دانلود کنید.  
۳. فایل زیپ را در یک پوشه دلخواه (مثلاً در درایو `C:\Program Files\V2RayPro` یا دسکتاپ) از حالت فشرده خارج کنید.  
۴. فایل `v2raypro.exe` را اجرا کنید.  
   - *نکته برای حالت TUN*: برای ساخت کارت شبکه مجازی Wintun، برنامه را به صورت **Run as Administrator** اجرا کنید.

---

## 💖 حمایت مالی از پروژه (Donation)

اگر V2RayPro برای شما مفید واقع شده است و قصد دارید از توسعه مداوم، به‌روزرسانی‌ها و سرورهای آن حمایت کنید، می‌توانید از طریق آدرس‌های رمزارز زیر دونیت کنید:

| نام ارز | شبکه / نماد | آدرس کیف پول |
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

## 📄 مجوز

این پروژه تحت مجوز MIT منتشر شده است.
