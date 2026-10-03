# Live Wallpaper for macOS — Loyiha rejasi

MacWall funksiyalariga o'xshash, ochiq kodli (open source) jonli wallpaper ilovasi. Kod, brend va wallpaper kontenti to'liq o'zimizniki bo'ladi.

## Asosiy parametrlar

| Parametr | Qiymat |
|---|---|
| Platforma | macOS 14 Sonoma+ (Apple Silicon asosiy) |
| Yondashuv | Native (Swift) |
| Monitorlar | Kamida 2 ta, har biriga alohida wallpaper |
| Video qo'shish | Drag-and-drop (hozircha onlayn kutubxonasiz) |
| Tarqatish | GitHub, open source |
| Ishlab chiqish | AI yordamida (Claude Code va h.k.) |
| Taxminiy muddat | 5–7 hafta (bo'sh vaqtda) |

## Texnologiya steki

- **Til / UI:** Swift 5.10+, SwiftUI
- **Desktop oynasi:** AppKit (`NSWindow`)
- **Video:** AVFoundation (`AVQueuePlayer` + `AVPlayerLooper`)
- **Effektlar:** SpriteKit (keyinchalik Metal)
- **Saqlash:** SwiftData yoki Codable JSON
- **Yangilanishlar:** Sparkle
- **Sandbox:** Yo'q (App Store'dan tashqarida tarqatiladi)

---

## 0-bosqich: Tayyorgarlik (1 kun)

- [x] Xcode'da macOS App loyihasini ochish (deployment target: macOS 14)
- [x] `Info.plist` ga `LSUIElement = YES` qo'shish (Dock'da ko'rinmaydi, faqat menu bar)
- [x] App Sandbox'ni o'chirish
- [x] GitHub repo yaratish, litsenziya tanlash (MIT)
- [x] Ilovaga o'z nomini berish ("MacWall" nomi va logotipi ishlatilmaydi)
- [x] Repo ildiziga `CLAUDE.md` qo'shish: arxitektura, kod uslubi, "macOS 14+, sandbox yo'q" qoidalari

## 1-bosqich: MVP — bitta video, bitta monitor (2–3 kun)

Butun ilovaning yuragi. Video desktop ikonkalari ostida, tizim wallpaper'i ustida ijro etiladi.

```swift
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                      backing: .buffered, defer: false)
window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.ignoresMouseEvents = true
window.backgroundColor = .black

let item = AVPlayerItem(url: videoURL)
let player = AVQueuePlayer()
let looper = AVPlayerLooper(player: player, templateItem: item) // referensni saqlash shart!
player.isMuted = true
let layer = AVPlayerLayer(player: player)
layer.videoGravity = .resizeAspectFill
```

- [x] `WallpaperWindow` klassi (desktop level, barcha Space'larda)
- [x] `PlayerController` (uzluksiz loop, ovozsiz)
- [x] Qattiq kodlangan video yo'li bilan test

**Natija:** ilova ochilganda video desktop orqasida loop bo'lib aylanadi.

## 2-bosqich: Ko'p monitor, kutubxona, menu bar (1 hafta)

### Ko'p monitor
- [ ] Har bir `NSScreen` uchun alohida `WallpaperWindow`
- [ ] `NSApplication.didChangeScreenParametersNotification` orqali monitor ulanishi/uzilishini kuzatish
- [ ] Monitorni `CGDirectDisplayID` orqali aniqlash va eslab qolish
- [ ] "Bitta video barcha monitorlarda" rejimi: bitta `AVPlayer` → bir nechta `AVPlayerLayer` (video faqat bir marta decode qilinadi)

### Kutubxona
- [ ] Drag-and-drop: SwiftUI `.dropDestination(for: URL.self)`
- [ ] Fayllarni `~/Library/Application Support/<AppNomi>/Videos/` ga nusxalash
- [ ] Thumbnail yaratish: `AVAssetImageGenerator`
- [ ] Videoni o'chirish va qayta nomlash

### Tizim integratsiyasi
- [ ] Menu bar: `MenuBarExtra`
- [ ] Login'da avtomatik ishga tushish: `SMAppService.mainApp.register()`
- [ ] Har bir monitor uchun tanlovni SwiftData'da saqlash

## 3-bosqich: Aqlli pauza va optimizatsiya (3–5 kun)

### Pauza holatlari
- [ ] Oyna yopilib qolganda: `NSWindow.didChangeOcclusionStateNotification` (to'liq ekranli ilovalar)
- [ ] Ekran/tizim uxlaganda: `NSWorkspace.screensDidSleepNotification`, `willSleepNotification`
- [ ] Batareyada ishlaganda: IOKit `IOPSCopyPowerSourcesInfo`
- [ ] Low Power Mode: `ProcessInfo.isLowPowerModeEnabled`
- [ ] Qizib ketganda: `ProcessInfo.thermalState`
- [ ] Har bir holat sozlamalarda yoqib-o'chiriladigan bo'lsin

### Optimizatsiya
- [ ] Import paytida HEVC (H.265) ga avtomatik konvertatsiya: `AVAssetExportSession` (Apple Silicon'da apparat decode)
- [ ] Videoni monitor o'lchamiga moslashtirish (ortiqcha 8K kerak emas)
- [ ] Activity Monitor va Instruments bilan o'lchash

**Maqsad:** video ijrosida CPU 2–5% dan oshmasin.

## 4-bosqich: Playlist, kun/tun rejimi, statik lock screen (1 hafta)

- [ ] Har bir monitor uchun playlist va almashish intervali
- [ ] Crossfade o'tish: ikkita `AVPlayerLayer` + opacity animatsiyasi
- [ ] Kun/tun rejimi: `NSApp.effectiveAppearance` ni KVO orqali kuzatish, light/dark playlistlarni almashtirish
- [ ] Statik lock screen: video kadrini PNG qilib chiqarish → `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` (Sonoma+ da lock screen va Mission Control shu rasmni ko'rsatadi)

## 5-bosqich: Interaktiv va ob-havo effektlari (1–2 hafta)

- [ ] Video ustiga shaffof `SKView` qatlami
- [ ] Effektlar: yomg'ir, qor, zarrachalar
- [ ] Ob-havo: Open-Meteo API (bepul, kalitsiz). WeatherKit pullik developer akkaunt talab qiladi
- [ ] Sichqonchaga reaksiya: `NSEvent.mouseLocation` ni timer bilan o'qish (oyna `ignoresMouseEvents` holatida qoladi)
- [ ] Parallax va zarrachalarning kursordan qochishi
- [ ] (Ixtiyoriy) Murakkab shader effektlar uchun Metal

## 6-bosqich: Video lock screen (eksperimental)

> ⚠️ Apple uchinchi tomon ilovalari uchun lock screen'ga video qo'yishning rasmiy API'sini bermaydi. Raqobatchilar hujjatlashtirilmagan usullardan foydalanadi va ular har macOS yangilanishida buzilishi mumkin.

- [ ] Alohida eksperimental modul sifatida tadqiq qilish
- [ ] Sozlamalarda "Experimental" belgisi bilan berish
- [ ] Ishlamasa, 4-bosqichdagi statik lock screen zaxira variant bo'lib qoladi

## 7-bosqich: Open source reliz (2–3 kun)

- [ ] README: GIF demo, o'rnatish yo'riqnomasi, arxitektura tavsifi
- [ ] GitHub Actions: har bir tag'da `.dmg` avtomatik yig'ish (`create-dmg`)
- [ ] Sparkle bilan avtomatik yangilanishlar (EdDSA imzosi)
- [ ] CONTRIBUTING.md va issue shablonlari
- [ ] Namuna videolar uchun litsenziyani tekshirish (Pexels, Pixabay, Coverr). Yaxshisi, videolarning o'zini emas, havolalarini berish

### Notarizatsiya haqida
Pullik Apple Developer akkauntisiz ($99/yil) ilova notarize qilinmaydi va foydalanuvchilar Gatekeeper ogohlantirishini ko'radi. README'da yechimni yozish kerak:

- System Settings → Privacy & Security → **Open Anyway**
- yoki terminalda: `xattr -dr com.apple.quarantine /Applications/<AppNomi>.app`

Homebrew cask'ga qo'shish ham notarizatsiya talab qilishi mumkin.

---

## Loyiha tuzilmasi

```
App/            → AppDelegate, MenuBarExtra
Engine/         → WallpaperWindow, PlayerController, ScreenManager
Library/        → VideoImporter, ThumbnailGenerator, HEVCConverter
Scheduling/     → PlaylistManager, AppearanceObserver
Power/          → PauseController (occlusion, battery, sleep, thermal)
Effects/        → WeatherService, ParticleScene
Settings/       → SwiftUI sozlamalar oynasi
```

## AI bilan ishlash qoidalari

- Har bir bosqich alohida branch'da
- Vazifalarni kichik qismlarga bo'lish (masalan: "faqat ScreenManager'ni yoz va monitor uzilganda test qil")
- Har bosqichdan keyin ikkala monitorda qo'lda test qilish. Ko'p monitorli xatolarni AI o'zi ko'ra olmaydi
- `CLAUDE.md` ni har bosqichdan keyin yangilab borish
