# Better Battery Menu Bar

An alternative macOS menu bar battery icon with a configurable low-battery threshold and audible reminders. Requires macOS 13 or newer.

## Build and run

Open `Package.swift` in Xcode to edit the project. To build a runnable app bundle:

```sh
./build-app.sh
open dist/BatteryBeacon.app
```

Use the app bundle to run the app, so macOS can identify it for notification permission. Click its menu-bar battery percentage, choose Enable notifications, and allow the system prompt. Select an alert threshold from 5% to 90% in five-point steps (default 10%). Settings persist between launches.

For regular use, move the app into Applications before enabling Launch at login. Login registration may require approval in System Settings → General → Login Items. This development build is locally signed; distribution to other Macs requires proper signing and notarization.

## Behavior

Uses IOKit power-source events, with additional checks at launch, after wake, and when opening the menu. Normal updates use macOS events. While the battery is at or below the alert threshold, a five-minute timer rechecks the battery and repeats the notification with the default system notification sound. Reminders stop on external power or above the threshold. Sleep can delay timers; waking checks the latest state without replaying missed alerts. Notification sound and presentation follow macOS notification, Focus, and volume settings. Sends an initial warning and repeats every five minutes while low and unplugged. Launching below the selected threshold also sends a warning. Notification failures allow retry on the next power event. If notifications were denied, enable them in System Settings → Notifications, then reopen the panel. Focus and system notification settings can silence alerts.

The panel displays the Mac’s internal battery. Macs without a battery show a no-battery message. Time estimates appear only when macOS supplies them. No network requests or administrator privileges are needed.

## Verify

```sh
swift test
```

Tests cover threshold crossing, duplicate suppression within five minutes, repeated reminders, rearming on power, startup below the threshold, and retry after a notification failure. Manual checks: enable notifications, change the threshold, reconnect power, wake from sleep, and toggle launch at login. Real discharge and login behavior require testing on the target Mac.

## License

[MIT](LICENSE)
