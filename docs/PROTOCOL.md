# Andromac protocol v1

Transport: WebSocket (`ws://<mac-tailscale-ip>:8765/`) over the Tailscale tunnel.
The Mac is the server, the phone is the client (the phone reconnects with backoff).

## Pairing
Mac generates a 32-byte random secret and shows it as `andromac://<ip>:<port>/<base64url secret>`
(QR in the UI, printed in the CLI). The phone scans or pastes it. Nothing else is exchanged.

## Encryption (on top of Tailscale's WireGuard)
- key = HKDF-SHA256(secret, salt="andromac-v1", info="msg-key", 32 bytes)
- Every WebSocket binary frame = `nonce(12) || ChaCha20-Poly1305(key, nonce, plaintext_json) || tag(16)`
- A frame that fails authentication is dropped and the socket is closed.
- Every plaintext carries `seq` (per-direction counter). The receiver rejects `seq <= last`
  (replay protection).

## Envelope (JSON)
```json
{ "seq": 1, "type": "notification", "ts": 1731600000000, "data": { ... } }
```

## Message types
| type | direction | data |
|---|---|---|
| `hello` | both | `{device, version}` |
| `notification` | phone→mac | `{id, key, pkg, app, title, text, sub, ts, otp?}` |
| `notification_dismiss` | phone→mac | `{key}` |
| `sms` | phone→mac | `{from, body, ts, otp?}` |
| `clipboard` | both | `{text, ts}` |
| `battery` | phone→mac | `{level, charging}` |
| `ping` / `pong` | both | `{}` |

`otp` is a pre-extracted code (4-8 digits near words like otp/code/verification), so the
Mac can copy it straight to the clipboard.

Planned next: `sms_send`, `notification_reply`, `notification_action`, `file_*`, `call_state`.

## v2 additions

### Transport
Each Mac and phone runs its own embedded Tailscale node (Go `tsnet`, see `tunnel/`). The Mac sidecar forwards
`tailnet:8765` to the app on `127.0.0.1:8765`; the phone opens a local proxy that dials the Mac's tailnet IP.
No separate Tailscale app is required. The first launch of each device shows a one-time sign-in link.

### Binary video packets
Plaintext inside the encrypted frame starts with byte `0x01`: `[0x01][flags][H.264 Annex-B access unit]`,
flags bit0 = keyframe (keyframes carry SPS/PPS). JSON messages start with `{`.

### Screen sharing
| type | direction | data |
|---|---|---|
| `screen_request` | mac→phone | ask phone to share (phone shows an approval notification) |
| `screen_started` / `screen_stopped` | phone→mac | `{w,h}` / `{reason}` |
| `screen_stop` | mac→phone | stop sharing |
| `keyframe` | mac→phone | request a keyframe |
| `mac_screen_request` / `mac_screen_stop` | phone→mac | Mac shows an Allow/Deny alert |
| `mac_screen_started` / `mac_screen_denied` / `mac_screen_stopped` | mac→phone | `{w,h}` / `{reason}` |
| `mac_keyframe` | phone→mac | request a keyframe |
| `input` | both | `{target?:"mac", k, ...}`, see below |

`input.k`: `down|move|up` (`x`,`y` in 0..1), `rclick`, `scroll` (`dy`), `text` (`t`), `key` (`c`: backspace|enter|esc|tab), `nav` (`a`: back|home|recents|notifications).
Scroll `dy` sign: to the phone, `dy>0` swipes up; to the Mac (`target:"mac"`), `dy>0` = finger moving down.
Input is ignored unless a share session is active and was approved by the user on the shared device.

## v3 additions
- `notification` gained `icon` (base64 PNG of the source app, sent once per package per connection), `canReply` (bool) and, from the Mac, `pkg` = bundle id.
- `notification_reply` mac→phone `{key,text}`: the phone fills the notification's own reply box (RemoteInput).
- `notification_open` mac→phone `{key,title}`: opens that conversation on the phone (tap-equivalent; falls back to tapping it in the shade via Accessibility).
- `mac_open_app` phone→mac `{bundle}`: brings that Mac app to the front.
- `input.k` gained `pinch` (`s` scale), `rotate` (`deg`), `selectall`, `paste`, `combo` (`m` modifiers, `c` key).
- Video: the sender drops delta frames only together with a keyframe request, and adapts bitrate to link backlog.
- A new connection replaces the active one only after its first frame authenticates.
- Terminal bridge: the Mac helper also exposes `tailnet:22 → 127.0.0.1:22`; the phone listens on `127.0.0.1:2222` and forwards to it.
