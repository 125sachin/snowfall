# Permissions

| Feature | Permission | Notes |
|---|---|---|
| Overlay, falling snow, display-bottom accumulation | none | |
| Pointer disturbance | none | `NSEvent.mouseLocation` reads the cursor position only. No event tap, no Input Monitoring. Clicks, keys and scrolls are never observed. |
| Window physics (snow on window tops) | none | Uses the window server's on-screen list (`CGWindowListCopyWindowInfo`): owner pid, window number, bounds, layer, alpha, front-to-back order. No titles, no pixels. Accessibility was evaluated and rejected: it exposes no windows for many apps (e.g. Electron/Chrome) and no stacking order. |
| Launch at login | none | `SMAppService.mainApp`; the user can review it in System Settings → Login Items. |

Behaviour:
- No permission prompts are needed. If a future macOS version starts gating the window list, window physics will see no windows and everything else keeps working.
- The app is not sandboxed (reading other apps' window geometry is not compatible with the App Sandbox).
- No analytics, no network access. Logs (`os.Logger`, subsystem `com.xcode.snowfall`) never include window titles.
