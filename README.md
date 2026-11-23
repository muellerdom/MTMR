# MTMR (minimal)

A stripped-down fork of [MTMR](https://github.com/Toxblh/MTMR) (My TouchBar My Rules) for the MacBook Pro Touch Bar.
It shows only the essentials: Escape, brightness, volume keys, play/pause and a clock.

Tapping the brightness (sun) button expands the Touch Bar into one slider per display in Apple's style,
using Apple's own laptop and monitor icons; monitors are labeled with their short name (for example
`P27h-30`). With more displays than fit, the row scrolls horizontally. The system's ✕ or another tap
on the sun closes it.
MTMR also adds the same sun button to the Control Strip. To have it where Apple's brightness button
was, remove Apple's button under System Settings → Keyboard → Touch Bar Settings → Customize Control
Strip.
External monitors are controlled over DDC/CI and follow the built-in display: whatever changes the
built-in brightness (its slider, the brightness keys, auto-brightness) is mirrored to them. Moving a
monitor's own slider sets an offset to the built-in display, which is kept from then on and saved
per monitor.

## Requirements

- MacBook Pro with Touch Bar, macOS 12 or later
- For brightness sync: an Apple Silicon Mac and a monitor with DDC/CI enabled in its on-screen menu,
  connected via USB-C/DisplayPort or an HDMI adapter. DisplayLink docks do not pass DDC through,
  and some cheap HDMI adapters and hubs don't either.

## Build

```sh
./build.sh          # universal, ad-hoc signed app in Release/MTMR.app
```

On first launch, grant MTMR Accessibility access (System Settings → Privacy & Security → Accessibility);
it needs it to send the Escape and media keys. Because the build is ad-hoc signed, macOS may ask again
after each rebuild.

## Menu bar

- **Edit preset…**: opens `~/Library/Application Support/MTMR/items.json`. Saving it reloads the Touch Bar.
- **Sync brightness to external display**: on by default. The line below it shows how many external
  displays were found and how many answered over DDC. If a monitor shows *0 answering*, DDC is not
  getting through (check the monitor's DDC/CI setting, or try another cable or adapter), then use
  **Rescan displays**.
- **Hide Control Strip**, **Start at login** (macOS 13+), **Quit**.

## Preset

`items.json` is a JSON array; `//` and `/* */` comments are allowed. Each item has a `type` and optionally
`align` (`left`, `center`, `right`), `width` (points) and `bordered` (`true`/`false`).

| type             | what it does                                      |
| ---------------- | ------------------------------------------------- |
| `escape`         | Escape key (aligned left by default)              |
| `brightnessDown` | brightness key down                               |
| `brightnessUp`   | brightness key up                                 |
| `brightness`     | sun button; expands into one brightness slider per display |
| `volumeDown`     | volume key down                                   |
| `volumeUp`       | volume key up                                     |
| `mute`           | mute key                                          |
| `play`           | play/pause key                                    |
| `timeButton`     | clock; `formatTemplate` (default `HH:mm`), optional `locale` and `timeZone` |

Item types from the full MTMR (weather, scripts, groups, …) are ignored. To return to the default
layout, delete `items.json` and restart MTMR. The default is:

```json
[
  { "type": "escape", "width": 64, "align": "left" },
  { "type": "brightness", "width": 40, "bordered": false, "align": "right" },
  { "type": "volumeDown", "width": 32, "bordered": false, "align": "right" },
  { "type": "volumeUp", "width": 32, "bordered": false, "align": "right" },
  { "type": "play", "width": 38, "bordered": false, "align": "right" },
  { "type": "timeButton", "formatTemplate": "HH:mm", "align": "right" }
]
```

## How brightness sync works

`BrightnessSync` reads the built-in display's level (private `DisplayServices` framework) every 100 ms.
When the level changes, it adds each monitor's offset, maps 0…1 linearly onto the monitor's range (read via DDC, usually 0…100) and
writes VCP code `0x10` through `IOAVServiceWriteI2C`. Writes run on a background queue and are coalesced,
so a fast slider drag sends only the latest value. Displays are re-scanned when the screen configuration
changes and a few seconds after wake. Monitors are matched to screen names by position, which is
exact for one external monitor; with several, the labels may be swapped.

## License

MIT. Based on MTMR by Anton Palgunov and contributors.
