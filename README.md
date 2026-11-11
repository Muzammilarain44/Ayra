# Ayra — Free Voice Assistant (Android + Windows)

**Ayra** is a free, on-device voice assistant built with Flutter — one codebase,
two apps: **Android mobile** and **Windows PC**. No paid API, no account, no
cloud key, no subscription. Speech recognition and speech synthesis use the
device itself; commands are answered by a local rule engine.

> Built by Muzammil. Named by him. Made to beat his friend's "Siri" — full
> premium, no shortcuts, no paid anything.

## What Ayra can do (all free, all on-device)

**Premium 3D hybrid effects (pure Flutter, no paid packages, no assets):**
a rotating 3D particle globe behind a ringed glass voice orb — drag the orb
and it tilts in real 3D, the rings spin on different planes, the glow
breathes while listening — and every card leans in 3D towards your finger.
More premium than TZ Nova's globe, built from code, not pictures.

| Say / type | Ayra does |
|---|---|
| `open YouTube` / `YouTube kholo` / `یوٹیوب کھولو` | Opens YouTube, Google, GitHub, WhatsApp, Gmail, Maps, Spotify, Facebook, Instagram, LinkedIn, Wikipedia, X, Stack Overflow, ChatGPT |
| `search cats on YouTube` | Searches on YouTube / Google |
| `what time is it` / `time kya hai` / `وقت کیا ہے` | Time and date |
| `calculate 15 * 4` / `12 + 8` | Safe calculator (no `eval`) |
| `note buy milk` / `show my notes` | Notes, saved on the device |
| `remember my name is Muzammil` / `yaad rakho mera naam Muzammil hai` | Remembers facts, recalls them, forgets on request |
| `set timer 5 minutes` / `remind me in 10 minutes to call Ali` | Timer with a spoken announcement |
| `tell me a joke` / `quote` | Jokes and quotes (English, Roman Urdu, Urdu script) |
| `convert 5 km to miles` / `convert 100 c to f` | Unit converter |
| `generate password` | Strong 16-character password |
| `battery` / `torch on` / `torch off` | Battery level, flashlight (phone) |
| `open Chrome` / `Chrome kholo` / `camera kholo` / `settings kholo` | Opens any installed app by name, camera, WiFi/Bluetooth/settings (Android) |
| `set alarm 7 AM` / `7 baje ka alarm lagao` | Sets an alarm in the system clock app (Android) |
| `volume up` / `volume kam karo` / `mute karo` / `unmute` | Media volume up/down, mute, unmute |
| `coin toss karo` / `dice roll karo` | Coin toss, dice roll |
| `stopwatch start karo` / `stopwatch band karo` | Stopwatch with spoken elapsed time |
| `Ayra band karo` / `app band karo` | Closes Ayra itself (an app can only close itself) |
| `call 03303094425` | Opens the dialer |
| Windows only: `organize desktop`, `empty recycle bin`, `lock pc`, `shutdown pc` | Desktop actions — always asks for confirmation first |

**Languages:** English, Roman Urdu and Urdu script — Ayra replies in the
language you used. Voice listening has an English / اردو switch.

## Honest limits

- Ayra **cannot unlock a phone** — no app can, the OS forbids it.
- Ayra **cannot close another app** — no app can, Android forbids it.
  It can close itself on "Ayra band karo".
- Ayra **cannot send a WhatsApp message by itself** — it opens WhatsApp, you send.
- Ayra **does not run in the background** with the app closed.
- **No free-form AI chat yet** — that needs a cloud API key, which costs money.
  The code has a single placeholder for it (`lib/ai_service.dart`); when a
  free key is available, that one file is where it plugs in. Nothing else
  changes.

## Get the Android app (APK)

**Easiest — GitHub Actions (no install needed):**
1. Push this repo to GitHub.
2. Open the **Actions** tab → **Build Android APK** → **Run workflow**.
3. Download the `ayra-debug-apk` artifact (or `ayra-release-apk`).
4. Send the APK to your phone and install it (allow "Install unknown apps"
   once for your browser/file manager).

**On your own computer (needs Flutter):**
```bash
flutter pub get
flutter build apk --debug        # debug APK: build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release      # release APK (same folder, app-release.apk)
```

**Launcher icon:** the app icon is pure XML, no image files —
`mipmap-anydpi-v26/ic_launcher.xml` (adaptive icon: navy-to-purple gradient
background + electric-blue orb ring + white "A") with a vector fallback in
`mipmap-mdpi/ic_launcher.xml` for older Android. The Windows `.exe` uses the
default icon (no `.ico` file, so the repo stays 100% text files).

## Get the Windows app (EXE)

On a Windows PC with Flutter installed:
```bash
flutter pub get
flutter build windows --release
```
The app is in `build\windows\x64\runner\Release\` — run `ayra.exe`.
(Or use the **Build Windows** GitHub Actions workflow and download the
`ayra-windows-release` artifact.)

## Run it while developing

```bash
flutter pub get
flutter run            # Android device / emulator
flutter run -d windows # Windows desktop
```

## Project layout

```
lib/
  main.dart            # Premium dark dashboard UI with the 3D hero
  command_engine.dart  # Pure-Dart rule engine (EN + Roman Urdu + Urdu script)
  calculator.dart      # Safe expression parser, no eval
  memory_store.dart    # Notes + memories saved on the device only
  ai_service.dart      # Placeholder for a future (free) cloud AI key
  services/
    voice_service.dart   # On-device speech recognition + TTS
    device_service.dart  # Links, battery, torch, Windows desktop actions
  widgets/
    globe_3d.dart        # Rotating 3D particle globe (pure Flutter)
    orb_3d.dart          # Ringed 3D voice orb with drag tilt
    tilt_card.dart       # Cards that lean in 3D towards your finger
test/
  command_engine_test.dart  # 30+ engine + calculator cases
  widget_test.dart          # Home screen + 3D hero smoke tests
```

## Privacy

Everything Ayra remembers lives on your device (SharedPreferences). The
only network use is opening the site or app **you** asked for. No analytics,
no account, no data leaves the device.

---

## Roman Urdu — Mukhtasar Guide

**Ayra** ek muft voice assistant hai — Android mobile aur Windows PC, dono ke
liye. Koi paid API nahi, koi account nahi, koi cloud key nahi. Bolna aur
sunna phone/PC khud karta hai; commands ka jawab device par hi banta hai.

**APK kaise milega (sab se asaan):** Repo GitHub par push karo → Actions tab →
**Build Android APK** → Run workflow → `ayra-debug-apk` download karo → phone
par install karo.

**Windows EXE:** Windows PC par `flutter build windows --release` chalao, ya
GitHub Actions se **Build Windows** workflow se artifact download karo.

**Ye nahi kar sakti:** Phone unlock nahi kar sakti (koi app nahi kar sakti),
kisi doosri app ko band nahi kar sakti (Android ye power kisi app ko nahi
deta — khud band ho sakti hai, "Ayra band karo"), WhatsApp message khud nahi
bhej sakti (WhatsApp khol deti hai, tum bhejo),
app band ho to background mein nahi chalti. Free-form AI chat abhi nahi — us
ke liye cloud key chahiye hogi; jab free key milegi to sirf
`lib/ai_service.dart` mein lagayenge.

---

## Fresh-install checklist (background service)

Fresh install par pehli dafa ON dabane se service start honi chahiye —
pehle ye fail hoti thi, is liye ye checklist hai. Test karne se pehle
purana app uninstall karo, phir naya APK install karo:

1. App kholo, orb ko haath mat lagao — seedha **Ayra Assistant ON** dabao.
2. Microphone ki permission aani chahiye — **Allow** karo. (ON tab tak
   start nahi hota jab tak mic allow na ho; Android 14+ mic ke baghair
   microphone-type foreground service start hi nahi hone deta.)
3. Service start honi chahiye aur **"Ayra chal rahi hai"** notification
   aani chahiye — us ke BAAD battery exemption ki screen aati hai.
4. Agar mic **permanently denied** ho to ON dabane par Settings ka
   button milta hai — Settings → Permissions → Microphone → Allow karo.
5. Khaamoshi mein loop khud band nahi hota; sirf OFF dabane se band hota hai.
