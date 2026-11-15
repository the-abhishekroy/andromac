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
