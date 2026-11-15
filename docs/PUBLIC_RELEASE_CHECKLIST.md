# Before a public release

Things that cannot be done from code alone:

1. **Mac signing and notarization.** Needs a paid Apple Developer ID. Without it macOS shows warnings and privacy permissions (Full Disk Access, Screen Recording, Accessibility) reset whenever the app's signature changes. Add Sparkle for updates.
2. **Android distribution.** Google Play restricts SMS, notification-listener, accessibility and overlay permissions. Plan for direct APK / F-Droid, or prepare a Play permissions declaration. Use a release keystore and enable R8.
3. **Name and trademarks.** "Andromac" contains the Android and Mac marks. Review before using it commercially.
4. **Tailscale terms.** Each user signs in with their own Tailscale account through the embedded node (tsnet, BSD-3-Clause). Confirm Tailscale's terms and device limits fit your distribution model.
5. **Legal.** Privacy policy (see PRIVACY.md), license file, third-party notices: Tailscale (BSD-3), Go (BSD-3), OkHttp (Apache-2.0), AndroidX / Jetpack Compose (Apache-2.0).
6. **Crash reporting / support channel** and an uninstall/cleanup path (sign out of the private network, delete `~/.andromac`).
