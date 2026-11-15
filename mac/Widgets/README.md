# Andromac widgets

WidgetKit extension (`AndromacWidgets.appex`, bundle id `app.andromac.mac.widgets`) with:

- Control Center (macOS 26+): toggle "Andromac connection" (Connected/Off) and button "View phone".
- Notification Center / desktop widget: small (phone, status, battery, last sync) and medium (adds Turn on/off and View phone buttons, last clipboard item).

## Build

    ./build-app.sh            # SwiftPM app, unchanged
    ./build-widgets.sh        # builds the appex, embeds it in dist/Andromac.app/Contents/PlugIns, re-signs both
    ./build-widgets.sh --install   # same + install to /Applications, register and relaunch

`./build-app.sh --install` still works on its own (no widgets). Needs `brew install xcodegen`. The Xcode project is generated from `project.yml`.

## How the app and widgets talk (no App Group needed)

- App -> widget: `WidgetBridge.swift` writes `~/.andromac/widget-status.json` and calls `WidgetCenter.reloadAllTimelines()` / `ControlCenter.reloadAllControls()`. The sandboxed extension reads it via the entitlement `temporary-exception.files.home-relative-path.read-only` = `/.andromac/` (see `Widgets.entitlements`).
- Widget -> app: App Intents post a `DistributedNotificationCenter` notification `app.andromac.widget.command` (`toggleConnection`, `connectionOn`, `connectionOff`, `openPhone`); the app executes them via `AppModel`.

An App Group (`group.app.andromac`) was not used: it requires a provisioning profile.

## Signing

Signed with the local identity "Andromac Local Signing" (self-signed, not trusted by Apple). See the status section of the report / below for whether macOS shows the widgets with it. If the widgets do not appear in the gallery:

1. Open Xcode > Settings > Accounts and sign in with an Apple ID (free is enough). Xcode creates an "Apple Development" certificate.
2. `security find-identity -v -p codesigning` shows `Apple Development: ... (TEAMID)`.
3. `TEAM_ID=XXXXXXXXXX ./build-widgets.sh --install`

(A paid Developer ID also works the same way.) Note re-signing the app with a different identity resets its macOS privacy grants (Screen Recording, Accessibility, Full Disk Access) once.

## Status of this machine (checked 2026-11-15)

- Xcode account exists but NO signing certificate has been created: `security find-identity -v -p codesigning` shows 0 valid identities and `xcodebuild -allowProvisioningUpdates` fails with `No "Mac Development" signing certificate ... with a private key`. Fix: Xcode > Settings > Accounts > select the team > Manage Certificates > "+" > Apple Development. Then `TEAM_ID=<your team id> ./build-widgets.sh --install`.
- App Groups need a paid program (not available to Personal Teams), so the file + DistributedNotificationCenter bridge is used instead.
- With the local self-signed identity the extension is embedded, validly sealed, sandboxed, and `pluginkit` lists `app.andromac.mac.widgets`. Whether the widget gallery offers it could not be confirmed headlessly (chronod logs nothing for it).
