# Privacy

Andromac has no servers of its own and collects no analytics.

- **Where your data goes:** directly between your own Mac and phone, end-to-end encrypted (ChaCha20-Poly1305 with a key from the QR pairing). The path runs over Tailscale's network (your own account); Tailscale's coordination service sees device names and addresses, never message, clipboard or screen content. Log upload to Tailscale is disabled.
- **What is read on the phone:** notifications (Notification access), incoming SMS for one-time codes (SMS permission), the clipboard, and, only during a session you start, the screen (screen capture) and touch injection (Accessibility).
- **What is read on the Mac:** the clipboard (items marked concealed by password managers are skipped), Notification Center's database (Full Disk Access) to forward notifications, and the screen only during a session you approve (Screen Recording, Accessibility).
- **Storage:** the pairing secret is stored on each device (`~/.andromac/secret` with mode 600 on the Mac, app-private storage on Android). Clipboard history (up to 100 items) is saved on each device (`~/Library/Application Support/Andromac/clipboard.json` with mode 600 on the Mac, app-private storage on Android) and swapped between your two devices every time they connect. Items marked concealed by password managers are never recorded. "Clear" deletes the saved history.
- **Control:** every screen-sharing or remote-control session needs an on-device approval, and a master switch turns the connection off completely.
