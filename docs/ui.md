# Display interface

The interface is designed for a 480×480 AMOLED viewed at arm's length. It uses a near-black background, high-contrast type, provider accents, and text alongside every status color.

## Overview

The overview automatically lays out one to four providers:

- One provider uses a large full-width card.
- Two providers use stacked full-width cards.
- Three or four providers use a two-column grid.

Each card shows the provider name and health, its most-used quota window, the current percentage, a local reset countdown, and a progress bar. Normal usage uses the provider accent, the first configured threshold turns amber, and the highest threshold turns red.

## Provider detail

Tap a provider to see up to three quota windows at once. Every row keeps its own percentage, progress bar, and reset countdown. Tap the back control to return to the overview.

The top physical button provides the same overview/detail toggle when touch is inconvenient. Detail opens on the first configured provider when entered with the button.

## Connection and data states

The header pill reports:

- `PAIRING` while waiting for the first desktop snapshot
- `LIVE` while the current model has an active transport
- `OFFLINE` after a link loss while retained data is still within its freshness window
- `STALE` once the retained snapshot is older than `staleAfterSeconds`

Offline content is partially faded; stale content is faded further. Provider rows separately report available, delayed, unavailable, or not signed in. Unknown percentages render as `--`, never `0%`.

## Alerts

When a quota window crosses a configured threshold, the display wakes and shows an eight-second bottom banner such as **Claude reached 90%**. Warning and critical banners use amber and red backgrounds. Progress bars continue to carry the warning color after the banner disappears.

Alerts are deduplicated by the host. Multiple simultaneous crossings are queued in severity order. Device audio remains optional and disabled for the first hardware release.

## AMOLED protection

- Brightness defaults to 55%.
- The display dims after five idle minutes by default.
- It turns off after 30 idle minutes by default.
- Lit content shifts through a one-pixel square once per minute.
- Touch, a button press, or a new model wakes the screen.

These values are configurable on the host and arrive with every accepted snapshot.

## Pairing reset

Hold the top physical button for five seconds. The firmware deletes all saved BLE bonds, restarts advertising, wakes the screen, and displays a confirmation banner. A short press never clears pairing.
