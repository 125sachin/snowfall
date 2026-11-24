# Permissions

| Feature | Permission | Notes |
|---|---|---|
| Overlay, falling snow, display-bottom accumulation | none | |
| Pointer disturbance | none | `NSEvent.mouseLocation` reads the cursor position only. No event tap, no Input Monitoring. Clicks, keys and scrolls are never observed. |
| Window physics (snow on window tops) | **Accessibility** | Documented AX APIs for window frames, plus the window server's on-screen list (`CGWindowListCopyWindowInfo`) for stacking order only: owner pid, bounds, order.  Reads only position, size, minimized state and subrole of standard windows of regular apps. Never titles or contents. No screen capture. |
| Launch at login | none | `SMAppService.mainApp`; the user can review it in System Settings → Login Items. |

Behaviour:
- Accessibility is requested only when the user presses the button in Settings → Interaction, after the
  explanation is shown. The system prompt is shown at most once per launch; later presses open System Settings.
- Trust is re-checked every 2 s; revocation immediately stops tracking and window snow is released as falling snow.
- Denied/unavailable: everything except window physics keeps working. "Continue without window physics" = leave it off.
- The app is not sandboxed (AX window inspection of other apps is incompatible with the App Sandbox).
- No analytics, no network access. Logs (`os.Logger`, subsystem `com.example.Snowfall`) never include window titles.
