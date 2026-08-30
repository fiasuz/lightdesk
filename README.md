# LiteDesk

Oddiy, faqat lokal tarmoq (LAN/Wi-Fi) ichida ishlaydigan masofadan boshqarish ilovasi
(AnyDesk'ning kichik versiyasi). Har bir platforma uchun alohida **native** ilova
sifatida yozilgan — Windows uchun C#/WPF (`windows/`), macOS uchun Swift (`macos/`).
Umumiy JS/Electron kodbaza yo'q.

## Imkoniyatlari

- Bitta kompyuterni ("host") boshqasiga ("viewer") ekranini ko'rsatish uchun ulashish
- PIN-parol bilan himoyalangan ulanish
- Viewer tomonidan sichqonchani to'liq boshqarish (harakat, chap/o'ng/o'rta tugma, scroll)

Klaviatura boshqaruvi qo'shilmagan — talab faqat ekranni ko'rish va sichqoncha edi.

## Wire-protokol

Ikkala native ilova ham bir xil protokolda gaplashadi (WebSocket handshake + JSON
control xabarlar + xom JPEG kadrlar, TLS yo'q), shuning uchun Windows host bilan
macOS viewer (va aksincha) muammosiz ishlaydi. Batafsil: har bir platforma papkasidagi
kod (`Protocol/WireMessages.*`).

## Windows uchun native ilova (C#/WPF)

`windows/LiteDesk.sln` — to'liq native Windows ilovasi (C#/.NET 8, WPF), alohida
`.exe`.

Qurish (Windows'da, .NET 8 SDK o'rnatilgan bo'lishi kerak):

```bash
cd windows/LiteDesk
dotnet publish -c Release
```

`LiteDesk.csproj`da `RuntimeIdentifier`/`SelfContained`/`PublishSingleFile` allaqachon
sozlangan, shuning uchun qo'shimcha flag kerak emas. Natija:
`windows/LiteDesk/bin/Release/net8.0-windows/win-x64/publish/LiteDesk.exe` — bitta
fayl, alohida .NET runtime o'rnatish shart emas.

Windows Defender Firewall host rejimini birinchi marta ishga tushirganda so'rov
ko'rsatishi mumkin — "Ruxsat berish" (Allow access) tanlang, aks holda boshqa
kompyuterlar ulana olmaydi.

**Diqqat:** bu native Windows ilova macOS'dagi muhitda (bu loyihaning asosiy dev
muhiti) yozilgan va hali birorta Windows mashinada build/run qilinmagan — WPF'ni
Windows tashqarisida kompilyatsiya qilib bo'lmaydi. Ishlatishdan oldin haqiqiy
Windows'da (yoki Windows CI runner'da) sinab ko'rish kerak.

## macOS uchun native ilova (Swift/AppKit+SwiftUI)

`macos/` — to'liq native macOS ilovasi (Swift Package Manager, AppKit skelet +
SwiftUI ekranlar, ScreenCaptureKit, CGEvent), alohida `.app`.

Build va testlar (mahalliy macOS'da, Xcode Command Line Tools bilan):

```bash
cd macos
swift build          # debug build
swift test           # 18 ta unit/integration test (WebSocket handshake real
                      # loopback TCP orqali, JPEG encode, mouse-koordinata
                      # matematikasi) — bularning barchasi bu muhitda o'tgan
```

Distributable `.app` yig'ish (ad-hoc imzo bilan, Apple Developer Program shart
emas):

```bash
macos/Packaging/build-app.sh 1.0.0
```

Bu skript `swift build -c release` qiladi, `macos/build/LiteDesk.app`ni qo'lda
yig'adi (SPM paketi — Xcode loyihasi emas, shuning uchun bunday), `codesign
--sign - --force --deep` bilan ad-hoc imzolaydi va `macos/dist/LiteDesk-1.0.0-mac.zip`
sifatida arxivlaydi. Ushbu muhitda sinaldi: `.app` muvaffaqiyatli ochildi,
oyna ko'rindi va toza yopildi.

**macOS uchun ruxsatlar** (host bo'lgan Mac'da): Ekranni yozib olish va
Accessibility ruxsatlari kerak — ilova "Ulashishni boshlash" tugmasi bosilganda
bularni o'zi so'raydi, lekin quyidagilardan ham qo'lda berish mumkin:

- **Tizim sozlamalari > Maxfiylik va xavfsizlik > Ekranni yozib olish** — LiteDesk'ga ruxsat bering
- **Tizim sozlamalari > Maxfiylik va xavfsizlik > Accessibility (Kirish imkoniyati)** — LiteDesk'ga ruxsat bering

**Diqqat — inson tomonidan qo'lda tekshirilishi kerak bo'lgan narsalar:**

- Ekranni yozib olish va Accessibility ruxsatlari berilgach, host↔viewer
  seansini ikkita haqiqiy Mac orasida (yoki bitta Mac'da ikkita nusxa
  orqali) to'liq sinab ko'rish — bu avtomatlashtirilgan muhitda TCC ruxsat
  dialoglari interaktiv tasdiqni talab qilgani uchun sinalmagan.
- Scroll yo'nalishi belgisi (`MouseInjector.swift`dagi `wheel1 = -clamp(dy)`)
  — bu faqat mantiqiy taxmin, real trackpad/sichqonchada teskari bo'lishi
  mumkin, kodda komment bilan belgilangan.
- Retina/ko'p-monitor kombinatsiyalarida sichqoncha koordinatalarining
  aniqligi (point-fazo hisob-kitobi).

## Cheklovlar (bu "yetarli" versiya uchun ongli soddalashtirishlar)

- Faqat bitta LAN ichida ishlaydi, internet orqali (turli tarmoqlar) ulanish uchun
  qo'shimcha relay/signaling server kerak bo'ladi — bu versiyada yo'q.
- Bir vaqtning o'zida faqat bitta viewer ulana oladi.
- Klaviatura orqali boshqarish yo'q, faqat sichqoncha.
- Video H.264 kabi kodek bilan emas, oddiy JPEG kadrlar (~8 fps) orqali uzatiladi —
  tez va sodda, lekin AnyDesk darajasidagi silliqlikni bermaydi.
- Faqat asosiy (primary) ekran ulashiladi.
