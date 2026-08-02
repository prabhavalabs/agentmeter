# Roadmap

AgentMeter has a working end-to-end macOS and Waveshare hardware prototype. Remaining release work focuses on reproducibility, packaging polish, and optional hardware features.

## Repository foundation — complete

- Public project structure, MIT license, contribution templates, and CI
- Architecture, hardware, setup, configuration, protocol, UI, and development guides
- Versioned device schema and privacy-safe fixtures
- Host, protocol, and native firmware tests

## Hardware bring-up — complete

- Verified ESP32-S3 board profile, USB upload, AMOLED, touch, button, AXP2101, and PSRAM
- Recorded pins and board-specific support layer
- Completed a 30-minute animated-display soak without resets or corruption

## Host data source — complete

- Persistent supervised CodexBar loopback server with a fresh bearer token per process
- Per-provider last-good caching for transient Claude and other provider failures
- Dashboard schema validation and allowlist normalization
- Live Codex, Claude, and Gemini acceptance
- Confirmed that identity, credentials, costs, and raw responses do not enter device messages

## Communication — complete

- Private encrypted BLE service, discovery, bonding, fragmentation, ACK, retry, and reconnect
- Fixed-size firmware reassembly with timeout and atomic model application
- USB serial fallback using the same parser
- Successful repeated live sends to the physical display

## Display interface — complete

- Responsive, scrollable one-to-eight-provider overview and provider-detail screens
- Reset countdowns and threshold-aware progress indicators
- Waiting, reconnecting, stale, unavailable, and provider-error states
- Recognizable Codex, Claude, and Gemini marks
- Persistent agent visibility, always-on, and full-view rotation settings
- Touch navigation and context-aware physical-button fallback
- Configurable dimming, screen-off, always-on override, and pixel shifting

## Alerts and macOS installation — complete

- Deduplicated warning and critical threshold events
- On-device alert banners and persistent progress colors
- Isolated macOS runtime and launch-at-login service management
- Service status, retained logs, and documented uninstall/update flow

## First public hardware release

- Publish signed source archives and prebuilt firmware binaries
- Add photographs and an enclosure or stand guide
- Complete an independent clean-Mac setup test from the documentation
- Decide whether to enable the board's ES8311 audio path for optional sounds

## Later ideas

- Linux and Windows host packages
- Additional display boards and enclosure files
- Historical sparklines and privacy-preserving local trend storage
- Native desktop notifications
- Multiple paired displays
- Secure over-the-air firmware updates
