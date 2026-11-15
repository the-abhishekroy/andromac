
## Payment apps and Andromac
Paytm, banks and UPI apps block themselves while an accessibility service, screen capture or an overlay permission is active, because malware uses them. Andromac therefore:
- never asks for "Display over other apps";
- keeps its control (accessibility) service OFF and switches it on only for the length of a Mac-control session, then off again (`A11yToggle`);
- screen capture runs only during a session.

One-time grant that lets it switch itself: `adb shell pm grant app.andromac android.permission.WRITE_SECURE_SETTINGS`.
