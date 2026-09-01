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

### Internet orqali ulash (Cloudflare Tunnel) — Windows

Host ekranida "Internet orqali ham ulash (Cloudflare Tunnel)" belgisini
yoqsangiz, ilova bundled `cloudflared.exe`ni fon rejimida ishga tushiradi va
lokal WebSocket serverni (`http://localhost:<port>`) bepul, vaqtinchalik
`https://xxxx.trycloudflare.com` manzili orqali internetga ochadi — router'da
port ochish yoki statik IP shart emas. Olingan manzil "Ulashishni boshlash"
ekranida ko'rsatiladi; shuni viewer tarafiga (Viewer ekranidagi "Internet"
rejimi, faqat manzil maydoni) berish kifoya.

`cloudflared.exe` git repoga commit qilinmagan — `LiteDesk.csproj`dagi
`EnsureCloudflared` MSBuild target'i uni birinchi `dotnet build`/`publish`da
avtomatik yuklab, `Tools/cloudflared.exe`ga joylaydi (keyingi buildlarda qayta
yuklamaydi). Bu internetga ulanish talab qiladi va faqat `curl.exe` mavjud
Windows 10/11'da ishlaydi.

Bu — "quick tunnel": manzil har safar tunnel qayta ishga tushganda o'zgaradi,
doimiy subdomain uchun alohida Cloudflare akkaunt/domen kerak bo'ladi (hozircha
qo'shilmagan). PIN endi internetga ochiq bo'lgani uchun `HostServer`ga oddiy
himoya qo'shildi: bitta IP manzildan 5 daqiqa ichida 5 marta noto'g'ri PIN
kiritilsa, o'sha manzil 5 daqiqaga bloklanadi, har bir noto'g'ri urinishdan
oldin ~500ms sun'iy kechikish qo'shildi.

**Diqqat:** bu qism ham (loyihaning qolgan Windows kodi kabi) haqiqiy
Windows'da build/run qilib sinalmagan — `EnsureCloudflared` target'ining va
`cloudflared` jarayonini ishga tushirish/URL o'qish mantig'ining ishlashini
haqiqiy Windows mashinada tekshirish kerak.

## macOS uchun native ilova (Swift/AppKit+SwiftUI)

`macos/` — to'liq native macOS ilovasi (Swift Package Manager, AppKit skelet +
SwiftUI ekranlar, ScreenCaptureKit, CGEvent), alohida `.app`.

Build va testlar (mahalliy macOS'da, Xcode Command Line Tools bilan):

```bash
cd macos
swift build          # debug build
swift test           # 29 ta unit/integration test (WebSocket handshake real
                      # loopback TCP orqali, JPEG encode, mouse-koordinata
                      # matematikasi, cloudflared URL parsing, viewer URL
                      # qurish) — bularning barchasi bu muhitda o'tgan, bitta
                      # tashqi (MouseInjectorTests/...AccessibilityTrustCheck)
                      # bundan mustasno: u haqiqiy Accessibility TCC ruxsatini
                      # talab qiladi va shu sababli headless CLI'da signal 11
                      # bilan qulaydi — bu loyihaning ushbu funksiyaga
                      # tegishli emas, o'zgarishlardan oldin ham shunday edi.
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

### Internet orqali ulash (Cloudflare Tunnel) — macOS

Host ekranida "Internet orqali ham ulash (Cloudflare Tunnel)" belgisini
yoqsangiz, ilova bundled `cloudflared`ni fon rejimida ishga tushiradi va
lokal WebSocket serverni (`http://localhost:<port>`) bepul, vaqtinchalik
`https://xxxx.trycloudflare.com` manzili orqali internetga ochadi — router'da
port ochish yoki statik IP shart emas. Olingan manzil "Ulashishni boshlash"
ekranida (nusxalash tugmasi bilan) ko'rsatiladi; shuni viewer tarafiga (Viewer
ekranidagi "Internet" rejimi, faqat manzil maydoni) berish kifoya — u
`wss://` orqali, portsiz ulanadi.

`cloudflared` git repoga commit qilinmagan — `macos/Packaging/build-app.sh`
uni birinchi paketlashda GitHub'dan yuklab (`macos/Packaging/.cache/`ga
keshlab), `lipo -create` bilan universal (arm64+amd64) binary qilib
`LiteDesk.app/Contents/Resources/cloudflared`ga joylaydi. `swift run` bilan
dev rejimida ishlatilganda (bundle resurslari bo'lmaganda) Homebrew
manzillariga (`/opt/homebrew/bin`, `/usr/local/bin`) yoki PATH'ga fallback
qiladi.

Bu — "quick tunnel": manzil har safar tunnel qayta ishga tushganda o'zgaradi,
doimiy subdomain uchun alohida Cloudflare akkaunt/domen kerak bo'ladi (hozircha
qo'shilmagan). PIN endi internetga ochiq bo'lgani uchun `WebSocketServer`ga
oddiy himoya qo'shildi: bitta IP manzildan 5 daqiqa ichida 5 marta noto'g'ri
PIN kiritilsa, o'sha manzil 5 daqiqaga bloklanadi, har bir noto'g'ri
urinishdan oldin ~500ms sun'iy kechikish qo'shildi (`swift test`da sinaldi).

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
- `cloudflared` binarysini haqiqiy yuklab olish, `build-app.sh` orqali
  universal (arm64+amd64) qilib `.app` ichiga joylash va uni ishga tushirib
  haqiqiy `https://xxxx.trycloudflare.com` manzil olish — bu muhitda sinaldi
  va muvaffaqiyatli o'tdi (real GitHub release yuklandi, `lipo`/`codesign`
  ishladi, bundled binary orqali jonli quick tunnel ochib, uning stderr
  chiqishidan URL to'g'ri o'qib olindi).
- Ikkita haqiqiy, turli tarmoqdagi qurilma orasida `cloudflared` orqali
  to'liq host↔viewer seansi (`wss://xxxx.trycloudflare.com`, ekran ulashish +
  sichqoncha/klaviatura) — buning uchun TCC ruxsat dialoglari interaktiv
  tasdiqni talab qilgani sababli headless muhitda sinalmagan, qo'lda
  tekshirilishi kerak.

## Cheklovlar (bu "yetarli" versiya uchun ongli soddalashtirishlar)

- LAN ichida to'g'ridan-to'g'ri ishlaydi; turli tarmoqlar orasida ulanish uchun
  ixtiyoriy Cloudflare Tunnel qo'shildi (yuqoridagi "Internet orqali ulash"
  bo'limlariga qarang) — o'z relay/signaling serveringiz kerak emas.
- Bir vaqtning o'zida faqat bitta viewer ulana oladi.
- Klaviatura orqali boshqarish yo'q, faqat sichqoncha.
- Video H.264 kabi kodek bilan emas, oddiy JPEG kadrlar (~30 fps) orqali uzatiladi —
  tez va sodda, lekin AnyDesk darajasidagi silliqlikni bermaydi.
- Faqat asosiy (primary) ekran ulashiladi.
