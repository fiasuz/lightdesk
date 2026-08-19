# LiteDesk

Oddiy, faqat lokal tarmoq (LAN/Wi-Fi) ichida ishlaydigan masofadan boshqarish ilovasi
(AnyDesk'ning kichik versiyasi). Windows va macOS'da ishlaydi.

## Imkoniyatlari

- Bitta kompyuterni ("host") boshqasiga ("viewer") ekranini ko'rsatish uchun ulashish
- PIN-parol bilan himoyalangan ulanish
- Viewer tomonidan sichqonchani to'liq boshqarish (harakat, chap/o'ng/o'rta tugma, scroll)

Klaviatura boshqaruvi qo'shilmagan — talab faqat ekranni ko'rish va sichqoncha edi.

## O'rnatish

```bash
npm install
npm start
```

## Foydalanish

1. Ikkala kompyuterda ham ilovani oching, ikkalasi ham bir xil Wi-Fi/LAN tarmog'ida bo'lishi kerak.
2. Boshqariladigan kompyuterda **"Bu kompyuterni ulashish"** ni tanlang, ekranni tanlang,
   port va PIN'ni tekshiring (yoki o'zgartiring), **"Ulashishni boshlash"** tugmasini bosing.
   Ekranda ko'rsatilgan IP manzil va PIN'ni boshqa kompyuterga ayting.
3. Boshqaruvchi kompyuterda **"Boshqa kompyuterga ulanish"** ni tanlang, host'ning
   IP manzili, porti va PIN'ini kiriting, **"Ulanish"** tugmasini bosing.
4. Ulangandan so'ng, viewer oynasidagi ekran ustida sichqonchani harakatlantirish,
   bosish va scroll qilish — barchasi host kompyuterda bajariladi.

## macOS uchun ruxsatlar (host bo'lgan kompyuterda)

macOS ekranni yozib olish va sichqonchani dasturiy boshqarishni cheklaydi. Host rejimida
ilova buni so'raydi/tekshiradi, lekin qo'lda ham berish mumkin:

- **Tizim sozlamalari > Maxfiylik va xavfsizlik > Ekranni yozib olish** — LiteDesk'ga ruxsat bering
- **Tizim sozlamalari > Maxfiylik va xavfsizlik > Accessibility (Kirish imkoniyati)** — LiteDesk'ga ruxsat bering

Ruxsat berilgach, ilovani qayta ishga tushiring.

## Windows uchun

Alohida ruxsat talab qilinmaydi, lekin Windows Defender Firewall birinchi ishga
tushirishda so'rov ko'rsatishi mumkin — "Ruxsat berish" (Allow access) tanlang, aks holda
boshqa kompyuterlar ulana olmaydi.

## Cheklovlar (bu "yetarli" versiya uchun ongli soddalashtirishlar)

- Faqat bitta LAN ichida ishlaydi, internet orqali (turli tarmoqlar) ulanish uchun
  qo'shimcha relay/signaling server kerak bo'ladi — bu versiyada yo'q.
- Bir vaqtning o'zida faqat bitta viewer ulana oladi.
- Klaviatura orqali boshqarish yo'q, faqat sichqoncha.
- Video H.264 kabi kodek bilan emas, oddiy JPEG kadrlar (~8 fps) orqali uzatiladi —
  tez va sodda, lekin AnyDesk darajasidagi silliqlikni bermaydi.
- Faqat asosiy (primary) ekran ulashiladi.
