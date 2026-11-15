# Andromac

One ecosystem for a Mac and an Android phone, over the internet, no cable and no shared Wi-Fi.

- Phone notifications and one-time codes on the Mac (and Mac notifications on the phone)
- Real-time clipboard sync both ways, with history on both devices
- View and control the phone from the Mac, and the Mac from the phone
- Built-in private network (Tailscale tsnet), no separate Tailscale app needed
- Everything is end-to-end encrypted by Andromac on top of the network's own encryption

## Layout
| Folder | What |
|---|---|
| `mac/` | SwiftUI menu bar + window app. `./build-app.sh --install` builds and installs `/Applications/Andromac.app` |
| `android/` | Kotlin / Jetpack Compose app. Build with the Gradle wrapper (`assembleDebug`) |
| `tunnel/` | Go module: the embedded Tailscale node (`andromac-tunnel` helper for macOS, gomobile `tunnel.aar` for Android) |
| `docs/PROTOCOL.md` | Wire protocol |
| `branding/` | Logo (`logo.svg`) |
| `PRIVACY.md` | What data goes where |
| `docs/PUBLIC_RELEASE_CHECKLIST.md` | What is still needed before a public release |

## Build
1. `brew install go openjdk@17 android-commandlinetools` and Xcode (for the Mac app).
2. `cd tunnel && go build -o build/andromac-tunnel ./cmd/andromac-tunnel`
3. Android library: `gomobile bind -target=android/arm64 -androidapi 28 -javapkg=app.andromac -o build/tunnel.aar ./mobile`, copy to `android/app/libs/`
4. Mac: `cd mac && ./build-app.sh --install`  ·  Android: `cd android && ./gradlew assembleDebug`

## Using it without a computer or adb (normal users)
1. Install the Mac app (drag to Applications; first launch: right-click, Open, until the app is notarized) and the Android APK from the GitHub release.
2. Sign in to the built-in private network on both devices with the same Tailscale account (free).
3. Scan the QR code on the Mac with the phone.
4. Grant the permissions the setup card lists (notification access, SMS, battery; on the Mac: Full Disk Access, Screen Recording, Accessibility).
5. **Controlling the phone from the Mac** needs Android's accessibility service. Andromac keeps it off so payment apps (Paytm, banks) keep working. Switch it on in Settings, Accessibility, Installed apps, Andromac when you want to control the phone; Andromac switches it off again by itself when the session ends. Power users can run `adb shell pm grant app.andromac android.permission.WRITE_SECURE_SETTINGS` once to make that fully automatic.
6. Viewing the phone's or Mac's screen, clipboard sync, notifications, SSH shortcuts and the widgets do not need adb.
