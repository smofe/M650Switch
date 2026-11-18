# M650Switch

A small macOS menu bar app that lets you hand a **Logitech Signature M650** mouse
back and forth between two Macs over Bluetooth, without opening System Settings
and without piling up dozens of stale "Logi M650" pairings.

<!-- Add a screenshot of the menu bar panel here: docs/screenshot.png -->

## Why this exists

The M650 has no Easy-Switch button: it can only remember **one** Bluetooth host.
Pairing it with a second Mac erases its bond with the first, and it comes back
with a new Bluetooth address every time. Sharing one M650 between two MacBooks
therefore means:

1. Hold the mouse's pairing button, open System Settings → Bluetooth on the other Mac, click *Connect*.
2. Repeat in the other direction tomorrow.
3. Watch System Settings fill up with old "Logi M650" entries that never go away on their own.

None of this can be fixed on the Mac side by copying pairing keys or similar
tricks — the bond lives in the mouse, and the mouse only keeps one. M650Switch
instead automates the re-pairing so that switching becomes:

> **Hold the button under the mouse for 3 seconds. The other Mac takes over.**

## How it works

| Step | What M650Switch does |
| --- | --- |
| Mouse leaves this Mac | Detects the disconnect and **yields** for a few seconds (default 10), so the *other* Mac wins the race. |
| Mouse is in pairing mode | Sees it advertising over Bluetooth LE and connects to it, which makes macOS start pairing. |
| macOS asks for confirmation | Clicks **Connect** on the system's "Connection Request from: Logi M650" prompt. |
| Pairing done | Removes stale "Logi M650" entries via System Settings → Bluetooth → *Forget This Device*. |

Run it on both Macs. Each one yields after losing the mouse, so pressing the
pairing button always sends the mouse to the Mac that doesn't currently have it.

## Why it needs Accessibility access

macOS does not let third-party apps pair or unpair Bluetooth devices silently:

- When an app initiates pairing, macOS always shows a **"Connection Request"
  prompt**, and there is no API to accept it programmatically.
- Requests to **unpair** a device are only honoured for Apple-signed processes.

The only remaining way is to press those buttons through the Accessibility API,
the same way assistive software does. M650Switch uses it in two narrow cases:

- **Pairing prompt:** only for ~25 seconds after M650Switch itself connected to
  the mouse, and only on a prompt that names the mouse. Pairing requests from
  any other device are never touched.
- **Cleanup:** only on System Settings → Bluetooth, and only for entries named
  "M650" that are marked *Not Connected*. Each step checks that the dialog is
  about the mouse before confirming; anything unexpected cancels the run.

Without Accessibility access the app still connects, and you click *Connect*
yourself.

It also needs **Bluetooth** access, to see and connect to the mouse.

## Requirements

- macOS 14 Sonoma or later (developed and tested on macOS 26)
- macOS system language set to **English** (cleanup and the prompt are matched by their English button titles)
- Xcode or the Command Line Tools (`xcode-select --install`) to build
- A Logitech Signature M650 (or M650 L); other single-host BLE devices can be configured, see below

## Setup

Do this on **both** Macs:

```sh
git clone https://github.com/smofe/M650Switch.git
cd M650Switch
./build.sh
open ~/Applications/M650Switch.app
```

Then:

1. Allow **Bluetooth** access when asked.
2. Grant **Accessibility** access: System Settings → Privacy & Security →
   Accessibility → enable *M650Switch* (the menu bar panel has a shortcut).
3. Tick **Open at login** in the panel.

**About signing:** `build.sh` creates a self-signed certificate called
"M650Switch Local Signing" in your login keychain on first run and signs the
app with it. Its only purpose is a stable code signature, so macOS keeps your
permission grants when you rebuild. It is not trusted for anything else and
can be deleted in Keychain Access at any time.

## Usage

Hold the button on the bottom of the mouse for about 3 seconds, until the
light blinks fast. Within a few seconds the mouse works on the other Mac.

The menu bar panel shows the connection state and lets you:

- pause automatic pairing,
- change the yield time (5–30 s),
- clean up stale pairings manually or after every switch,
- open the log (`~/Library/Logs/M650Switch.log`).

## Using it with another device

Everything device-specific is in [`Sources/Config.swift`](Sources/Config.swift):
the Bluetooth name, vendor ID and product ID. Look them up with:

```sh
ioreg -r -c IOHIDDevice -l | grep -E '"(Product|VendorID|ProductID|Transport)"'
```

This only makes sense for Bluetooth LE devices that, like the M650, remember a
single host.

## Limitations

- The cleanup automates System Settings, so it can break when Apple changes
  that UI. If it does, it stops safely and logs where.
- If the mouse is bonded to a Mac that is asleep or off and starts advertising,
  the other Mac may take it over. That is usually what you want.
- Not affiliated with or endorsed by Logitech. "Logitech" and "M650" are
  trademarks of their respective owners.

## Project layout

```
Sources/
  App.swift             entry point, menu bar item
  MenuPanel.swift       SwiftUI panel
  AppState.swift        wires everything together, hand-off logic, settings
  Pairer.swift          finds the mouse in pairing mode and connects (CoreBluetooth)
  PromptAcceptor.swift  confirms the system pairing prompt (Accessibility)
  Cleaner.swift         removes stale pairings via System Settings (Accessibility)
  HIDWatcher.swift      knows whether the mouse is connected here (IOKit)
  AX.swift              small Accessibility helpers
  Config.swift          device constants, logging
Resources/Info.plist
build.sh                build, sign and install
```

## License

[MIT](LICENSE)
